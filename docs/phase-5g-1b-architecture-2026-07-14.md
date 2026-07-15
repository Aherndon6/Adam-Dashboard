# 5G-1B — Holding → Allocation → Payout Event Lifecycle: Implementation-Ready Architecture Package

**Date:** 2026-07-14 (Thursday) · **Phase:** 5G-1B (roadmap §4 / §3.0 #6). **Type:** Architecture & implementation-readiness package. **Docs only. No implementation authority.** No application code, SQL, migration, RLS, RPC, test, `BUILD_TS`, staging, or production change is created or executed by this document.
**Standing:** `AGENTS.md`, `CODEX_STATUS.md`, `docs/roadmap/canonical-roadmap.md`, cleared 5G-1D scope, the Do-Not-Touch list, and Wendy-confirmed workflow win on any conflict. **Balance-free** — dollar amounts and account balances live only in the approved Value Card / local execution copies, never here.
**Purpose:** let a future Code session implement 5G-1B **without reopening core architecture questions**. Draft SQL *structure* is described; **no migration file is created or run.**
**Provenance:** roadmap §4 (1B reframing), §18 (Account Composition rider), §12.3 (T-6); the 2026-07-14 Fable documents (Adoption Review §4.1; Targeted Sequencing Review; Boundary Clarifications; Account Composition Scope); **and the controlling RG-1 review `Fable 5G-1B Architecture Review - 2026-07-14.md` (verdict ADOPT WITH CHANGES; C-1…C-5 folded into this revision)**. Grounded against `docs/phase-5g-1d-gatec-register-2026-07-13.md`, `docs/phase-5g-1d-migration.sql` (wrapper + Option B), `docs/phase-5g-1c-2-migration.sql` (`goal_funding_snapshots`), `docs/phase-5g-1c-2.1-hotfix.md` (`wewe_*` doctrine), `docs/phase-5g-1-migration.sql` (`outflow_events` append-only precedent), `docs/phase-5g-1d-snapshot-correction-procedure-2026-07-10.md` (Option B / reopen).
**RG-1 corrections folded (2026-07-14):** C-1 basis_adjustment · C-2 `effective_at timestamptz` · C-3 reversal-linkage integrity · C-4 non-overlapping write planes · C-5 authenticated-owner-REST execution path. **Two final contract corrections (Adam-directed, post-RG-1):** `effective_at` is **`timestamptz`** (not date; closed-week derived via governing tz) and **`correction` is removed** — four financial event types, corrections = reversal + replacement. **B-6/B-7/B-8/B-10/B-11/B-12 are Adam-approved (§19); no B-decision remains open.** Package is implementation-ready pending the spec's ChatGPT/conformance pass + build-gate approvals.

---

## 1. Executive architecture decision

**RG-1 status (2026-07-14):** Fable 5G-1B Architecture Review **received** — verdict **ADOPT WITH CHANGES** (C-1…C-5 blocking, all schema/RPC-contract completions; B-11/B-12 added; B-10 amended). The core design is confirmed and **not reopened** (Branch (a) rejected in every case examined, incl. restore). This document is **revised in place** to fold C-1…C-5; it becomes implementation-ready **only after** these corrections are incorporated (done here) **and Adam approves** (spec approval). Provenance: `Fable 5G-1B Architecture Review - 2026-07-14.md` (Adam's copy; `docs/roadmap/archive-index.md`).

**Verdict: ADOPT an append-only domain event ledger (`holding_events`) as the sole 5G-1B write surface, with a derived read-model (projection) for current held/released state — Branch (b) of roadmap §4 item 2.** One new **owner-governed `SECURITY DEFINER` RPC** (`record_holding_event`) appends events; **no snapshot write path is re-opened**; `goal_funding_snapshots` is never rewritten. Current held balance and release history are **derived** from a **frozen opening basis (the retained `wewe_*` snapshot rows) plus ledger basis-adjustments, minus net executed releases** (corrected per C-1 — a release-only fold against a permanently-frozen basis could not represent a payout exceeding that basis, future funding, or a new obligation).

**Corrected one-line architecture (RG-1):** *two planes, two write paths, zero overlap — the eligible nine write through the wrapper/Option B (progress plane); the excluded holdings (`wewe_rccl`/`wewe_dcl`) write through `record_holding_event` (cash plane: basis + releases); each path rejects the other's goal set (C-4).*

**Why (one paragraph):** after 5G-1D Gate C, every snapshot write path is revoked (G-01…G-08) and the only granted entry points are the closeout wrapper and Option B (owner-gated) — the roadmap's F-01 finding, now *executed*. A release record therefore has **no sanctioned home** unless 1B adds one. An append-only ledger (a) matches the one-append-only-convention doctrine (C2) already instantiated by `outflow_events`; (b) supplies the **durable transfer identity** the `weekly_tasks` positional-keying defect showed the system lacks (`db2704f` fixed it cosmetically; identity is still positional); (c) leaves the just-locked snapshot grant matrix **byte-untouched**; (d) is **rollover-neutral** (obligation + `effective_at`-timestamp keyed, not `week_num`-keyed — adds nothing to the AF-2 seven-object inventory); and (e) makes correction trivially safe (reversal + replacement; never edit history). Branch (a) — a governed current-state table — is rejected as the primary model because it re-introduces mutable state, complicates correction/replay, and provides no forcing function for the L3 ledger the roadmap says "rides 1B" (roadmap §8 / P8).

**Selected design in one line:** `holding_events` (append-only ledger, owner-only writes via `record_holding_event`) + `holding_state` (derived read view) + `goal_funding_snapshots` unchanged (cumulative funded progress) → **current held = frozen opening basis + net basis adjustments − net executed releases** (C-1).

---

## 2. Current-state grounding (repository facts — authoritative)

- **Post-Gate-C grant posture (approved, executes at Gate B):** old recon RPC **REVOKE** (G-01); `repair_commitments_for_week` **REVOKE** (G-02, zero callers); `save_goal_funding_snapshots` direct EXECUTE **REVOKE** (G-03); `goal_funding_snapshots` table INSERT/UPDATE **REVOKE** (G-04/05); `weekly_reconciliations` INSERT/UPDATE/DELETE **REVOKE** (G-06/07/08); `deleteRecon` **RESTRICT** (G-09); wrapper `save_weekly_closeout_with_snapshots` **GRANT** authenticated EXECUTE (G-10); Option B `correct_goal_funding_snapshot` **GRANT** authenticated EXECUTE, **owner-only enforced in-body via `public.is_owner()`** (G-11). Only granted write entry points post-lockdown: **wrapper + Option B**.
- **`goal_funding_snapshots` schema:** `(id uuid PK, model_year int, week_num int [CHECK 1..31], goal_id text FK goal_registry, funded_amount numeric(12,2) [CHECK ≥0], source text [CHECK ∈ {opening_anchor, reconciliation, correction}], created_by_user_id uuid FK auth.users, created_at, updated_at)`, `UNIQUE(model_year, week_num, goal_id)`. **`funded_amount` = observed cumulative funded progress at that week's end — NOT current cash held** (5G-1C-2.1 doctrine; payout ≠ zeroing).
- **`wewe_rccl` / `wewe_dcl`:** two Week-5 `source='correction'` snapshot rows recording cumulative funded PROGRESS for the RCCL/DCL cruise holds. **Excluded from the eligible nine** (the wrapper's server-derived closeout set: adam_ira, wendy_ira, wendy_sep, alaska, bailey_529, bryce_529, preston_529, bryce_vehicle, christmas_cruise). Executed once in production; templates are `-1` sentinels; values live in the Value Card only.
- **Option B (`correct_goal_funding_snapshot`)** is the correction precedent to mirror: owner-only (`is_owner()` → `42501`); **no Week-5** (`p_week_num=5` rejected — anchor is guarded-SQL only); monotonic bounds (reject below-preceding / above-following effective value); **call-through** the snapshot RPC (no direct table write); `source='correction'`.
- **`outflow_events` (5G-2) is the append-only precedent:** `(id, created_by_user_id nullable, planned_outflow_id FK, event_type text, amount_cents bigint, created_at, NO updated_at)`; audit fields immutable via trigger; `ON DELETE RESTRICT`; **no hard delete via app/RLS**; RLS `TO authenticated`, anon revoked. `outflow_events` carries **no FK to `transactions`** — splits-agnostic; the 5G-2 spec asserts it never writes `/rest/v1/transactions`.
- **5G-1A** reclassified RCCL/DCL from the `'goal'` sentinel to **AMEX Savings holding** (holding labels; `_amxHold` mechanics; paycheck-cleared readiness note). The AMEX holding invariant is presently **advisory / one-sided**.
- **Real payouts:** RCCL ~Cal Wk 30 (~Aug 1) — **retroactive** by the time 1B lands (mid-trip); DCL ~Cal Wk 41 (~Oct 17) — the **live deadline** and the calendar-forced bound on this phase.

---

## 3. Scope and non-goals

**In scope:** the durable modeling of a holding-funded obligation's release/payout lifecycle for **RCCL and DCL** (the two AMEX Savings cruise holds); the `holding_events` ledger + `record_holding_event` RPC + `holding_state` read-model; the engine seam (a 1A.5-style carve-out) surfacing releases in the weekly model (holding drawdown, "Transfers to execute", Funding Plan); UI surfacing (holding rows show held → released); retroactive RCCL release entry; DCL live entry; the terminal disposition of the `wewe_*` correction rows; the queryable release state that unblocks **1B-S4** (former 5G-1E); tests (static + e2e for the release path). Golden-master recapture **only if** engine outputs change (Adam approval).

**Non-goals (explicit):** general goal CRUD/reprioritization (5G-4b); physical funding-target unification (5G-4a); the **L2 row-mutation audit log** (D8 — a distinct tier; do NOT conflate with this L3 domain ledger); **any change to the Week-5 opening anchor** or to `goal_funding_snapshots` grants/schema; **hard AMEX invariant enforcement** (that is 1B-S4); the Budget-identity change; any **5G-2 planned-outflows build** (5G-2 is a separate phase — 1B must not depend on it, and vice-versa); any **second Available/Free cash calculation** (§10); a checking-account view (5G-3); Truist Savings modeling (rider only, §10/§14).

---

## 4. Domain model and lifecycle

**Two-plane model (corrected, C-1/C-4).** *Progress plane* = `goal_funding_snapshots` for the **eligible nine** (cumulative funded progress, closed-week basis — unchanged, monotonic non-decrease; written only by the wrapper/Option B). *Cash-location + basis plane* = `holding_events` for the **excluded holding obligations** (`wewe_rccl`/`wewe_dcl`) — append-only record of **basis** (opening + adjustments) and **releases**. **Zero overlap:** each write path rejects the other's goal set (C-4). Held-balance doctrine (corrected):

> **current held = frozen opening basis (retained `wewe_*` snapshot row) + net basis adjustments (ledger) − net executed releases (ledger)**

*Why the basis plane is needed (C-1):* the excluded obligations' progress plane is **permanently frozen** after Gate C (the wrapper writes only the nine; Option B rejects the excluded set; direct snapshot writes are revoked). A release-only fold against a frozen basis hard-blocks three reachable cases: a payout **exceeding** the frozen basis (a DCL price/tax delta), any **future funding** of a holding obligation, and any **new** holding obligation. `basis_adjustment` (§4-events) is the ledger-side analogue of Option B for the excluded set — the sanctioned pressure valve. **Over-release stays a hard reject with no override flag**; the valve is a prior-or-same-operation `basis_adjustment` (C-1). `funded_amount` stays cumulative progress; historical snapshot rows stay frozen; **no future snapshot write ever occurs for excluded holding obligations.**

**Obligation:** an identity for a holding-funded commitment. v1 obligations: `wewe_rccl`, `wewe_dcl` (the existing snapshot `goal_id`s — reused as the obligation key; C-4 adds an FK to `goal_registry(goal_id)` + an in-RPC **holding-set** membership check, no new registry object — B-4 stands).

**Event set (FOUR financial event types — final; `correction` removed):** `basis_adjustment` · `payout_authorized` · `payout_executed` · `reversal`. Positive magnitudes; effect = f(event_type); **type-aware fold ordered `(effective_at, created_at, id)`, reversed rows excluded** (C-2/C-3). **All financial state folds only from these four types.**

**Correction workflow (not an event type).** A value error is corrected by a **two-step workflow**, never an amount-bearing `correction` event: (1) a **full `reversal`** of the erroneous event (annuls it exactly); (2) a **new replacement event** (`basis_adjustment` / `payout_*`) carrying the corrected facts, with its **own `idempotency_key`** and its own note/evidence. Rules: one event may be **reversed at most once** (`UNIQUE(related_event_id)`); a **`reversal` cannot itself be reversed** (target type ∈ {`basis_adjustment`,`payout_authorized`,`payout_executed`}); the two steps are linked in **operator evidence** or an optional **non-financial `correlation_id`** (never affects folding). *Rationale for removing `correction`: reversal + replacement represents every value-correction case with append-only, deterministic folding and no unique state effect — a second amount-bearing supersession type only adds an ambiguous double-supersede fold path (two corrections claiming one target).* **Explicit non-events:** funding of *eligible* goals (wrapper's job — never here, C-4); **cancel** (= a `reversal` of the intent event); opening/migration events for RCCL/DCL (the retained Week-5 `wewe_*` rows are the basis; fabricated historical snapshots prohibited); a "refund-to-household" type (any cash exit is `payout_executed`; `note`/`evidence_ref` records the counterparty).

**Lifecycle states (derived from the ledger, not stored as mutable status):**

| State | Meaning | Derivation |
|---|---|---|
| **holding_funded / holding_increased** | Opening basis exists / basis rose | frozen `wewe_*` row (opening) + `basis_adjustment` events |
| **held** | Basis not yet released | basis − net released > 0 |
| **payout_authorized** | Release *intent* recorded | ledger `payout_authorized` event |
| **payout_executed** | Cash actually left the AMEX hold | ledger `payout_executed` event |
| **released** | An execution recorded against the obligation | Σ `payout_executed` net of reversals |
| **partial_payout** | Released > 0 and < basis | net released < basis |
| **full_payout** | Released == basis | net released == basis (payee-agnostic) |
| **reversed** | A prior event annulled by a `reversal` | ledger `reversal` → `related_event_id` |
| **corrected** | Result of the **correction workflow** = a `reversal` + a new replacement event (not a distinct event type) | reversed target excluded from the fold; replacement folds normally |
| **terminal** | Fully paid + attested; no further events expected | full_payout + attestation flag; **advisory only** (no terminal marker minted — Q6) |

**Release intent vs cash execution are SEPARATE events.** `payout_authorized` (intent) and `payout_executed` (cash left AMEX) are distinct rows: intent feeds "Transfers to execute"; reconciliation attests the *executed* leg. **Execution-only is permitted** when authorization and movement are the same runbook'd sitting, and for retroactive entries. **Refined per B-5:** when `effective_at` materially precedes `created_at`, the read-model labels the row **"retroactive entry"**, NOT "execution without intent" — the deliberate RCCL case must not carry a permanent anomaly flag. A failed/canceled transfer after intent = a `reversal` of the intent.

**Duplicate handling.** `idempotency_key UNIQUE` (RPC returns the existing id on same-key retry) **plus** a documented key convention (`obligation|type|effective_at|magnitude|seq`) **plus** a read-model **`duplicate_suspect`** flag (same obligation+type+magnitude+`effective_at` under *distinct* keys) — idempotency protects same-key retries; the flag catches different-key re-entry.

**Duplicate prevention:** every event carries a client-or-operator-supplied **`idempotency_key`** (`UNIQUE`), plus a natural guard (an obligation cannot be `payout_executed` for more than its held basis — §8). Re-submitting the same `idempotency_key` returns the existing event id (idempotent), never a second row.

---

## 5. Chosen schema / event design

**Model: append-only event ledger + derived projection (hybrid read).** The ledger is the source of truth; the projection is a **stateless derived read** (a SQL view or an app-side reducer), never an independently-writable table.

- **Why safer:** no mutable current-state row to corrupt; every change is an appended, attributed, timestamped fact; reversal (and replacement) is additive; the closed snapshot surface is untouched.
- **Reversal & correction-workflow semantics:** never edit or delete a row. A wrong event is annulled by a **`reversal`** (full-annul: same magnitude, opposite effect, `related_event_id` → the target). A **value correction** is that `reversal` **plus a new replacement event** carrying the corrected facts (its own `idempotency_key`); there is **no `correction` event type**. Both steps are owner-only.
- **Replay & reconstruction:** the full state at any point is a **type-aware** `fold(events ordered by (effective_at, created_at, id))` with superseded/annulled rows excluded (C-2/C-3). A restore replays the ledger; the projection is rebuilt deterministically — no stored state to reconcile.
- **Reconciliation behavior:** the executed-leg sum per obligation is attested against the AMEX statement at close (the release is **not** a closeout write — §7); the residual is the Account Composition rider's "Unattributed (timing/interest)" (§10).
- **Impact on frozen 5G-1D snapshots:** **none.** No snapshot row read, rewritten, re-granted, or re-CHECKed. The ledger joins to snapshots by `goal_id == obligation_key` for the *progress* number only.
- **Future compatibility:** the same append-only + immutable-audit pattern as `outflow_events` (5G-2) and the transaction-extension/sidecar convention TX-SPLIT instantiates — so 5G-2 set-asides and 5G-3 composition read the ledger without retrofit. 5G-3 later *reads* held/released for AMEX Spoken-For; it does not write here.
- **Migration/rollback complexity:** one additive table + one trigger + one RPC + one view; drop-in-reverse rollback with the table inert (ungranted) first. No data migration of existing rows (the `wewe_*` snapshot rows are the *basis*, not moved).

---

## 6. Write-surface contract

**The only sanctioned 5G-1B write path is `public.record_holding_event(...)` — one owner-governed `SECURITY DEFINER` RPC appending to `holding_events`.**

- **Revoked paths stay revoked:** 1B re-opens **none** of G-01…G-08. It adds no grant to any snapshot/reconciliation surface.
- **One RPC vs many:** **one** RPC with a validated `p_event_type` (mirrors `outflow_events`' single-table/`event_type` precedent and Option B's single-correction-RPC precedent). Rationale: one audited routing point, one owner gate, one idempotency guard; narrowly-scoped-per-type RPCs would multiply the grant/authz surface for no safety gain. (If the spec later finds a type that needs a materially different signature, it may split — but the default is one.)
- **Direct table-write posture:** **prohibited.** `holding_events` INSERT/UPDATE/DELETE are **revoked** for `anon` and `authenticated`; only the definer-owner RPC writes. Immutable audit fields (`created_by_user_id`, `created_at`, `idempotency_key`) enforced by a BEFORE-UPDATE/DELETE trigger that raises (append-only), matching `outflow_events`.
- **Service-role vs authenticated caller (corrected, C-5):** the RPC is granted `authenticated` EXECUTE (routing only), **owner-gated in-body** via `public.is_owner()` (→ `42501` for non-owner) — the Option B pattern. `is_owner()` keys on `auth.uid()`; **in the SQL editor `auth.uid()` is NULL → `is_owner()` false → the gate correctly fails**, so a SQL-editor write is *not* a valid path (a null-actor bypass would be a hole and would strip `created_by_user_id` from the most important money events).
- **Production execution path (corrected, C-5 — normal writes are authenticated owner REST calls, NOT SQL-editor writes):**
  - **Normal:** an **authenticated owner REST/RPC call** — real owner JWT, `auth.uid()` present, actor durably stamped, Gate-2 / Proof-A real-caller procedure (the same pattern already used to exercise Option B). This applies to the real RCCL/DCL `payout_executed` sittings (RG-3 runbook).
  - **SQL editor:** **read-only** verification and evidence queries; **no routine holding-event writes** (it cannot pass the owner gate).
  - **Service role:** **break-glass disaster recovery only** — separately authorized, separately evidenced, documented in the restore-runbook, out-of-band, **never the normal operator path**.
  - Wendy's browser never writes (§7 authz).
- **Basis-adjustment + release atomicity (C-1 — recommended safer contract):** for the exceeds-frozen-basis case, `record_holding_event` records the `basis_adjustment` **and** the `payout_executed` **atomically in one transaction** (two distinct append-only rows, committed together) — the **recommended safer contract**, because it commits both facts with no intermediate window where the basis is raised but the payout unrecorded, and the aggregate over-release check (§8) passes at commit over the combined set. Ordinary single-fact events remain one-row-per-call; separate sequential calls (basis first, then payout) are **permitted** but are the fallback, not the default. There is **no override flag** — the basis adjustment is the only valve.
- **Idempotency:** `idempotency_key UNIQUE`; a repeat returns the existing event id. The RPC is safe to retry (an atomic basis+release call carries one key per row, or a compound key — spec-locked).
- **Retry behavior:** network/2xx-ambiguity retries are safe (idempotent by key); the browser validates the persisted event (P1-1 pattern from 5G-1D) rather than trusting a bare 2xx.
- **Authorization failures:** non-owner → `42501`; malformed/over-release/duplicate-natural-key → typed exceptions with verbatim reject phrases (staging-matched, Gate-2 style).
- **Audit evidence:** the ledger itself (append-only, actor, timestamp, `idempotency_key`, `note`) + a line appended to `docs/execution-ledger.md` for each production sitting + the closeout doc.

---

## 7. RLS / grant / authorization model

| Object | Ownership | RLS / grant posture |
|---|---|---|
| `holding_events` (table) | `postgres` (trusted owner, == recon/snapshot/wrapper owner — P0-3 invariant) | RLS enabled; **SELECT** policy `TO authenticated` via `can_write_financials()`/household gate; **INSERT/UPDATE/DELETE REVOKED** from `anon` + `authenticated` (writes RPC-only); immutable-audit trigger blocks UPDATE/DELETE structurally |
| `holding_state` (view) | `postgres` | SELECT `TO authenticated`; read-only derivation; no writes possible |
| `record_holding_event` (RPC) | `postgres`, `SECURITY DEFINER`, `search_path=public,pg_temp` | GRANT `authenticated` EXECUTE (routing); **owner-only in-body** (`is_owner()` → `42501`); anon EXECUTE = false |

- **Owner-only vs writer:** all `holding_events` writes are **owner-only** (Adam). This is stricter than the Register's `can_write_financials()` writer posture because holding releases are money-movement facts, and matches Option B.
- **Wendy's role (`household_admin`):** **read** `holding_state` / `holding_events` (household financial visibility) — **no write** (the RPC rejects `is_owner()=false`, exactly as Option B rejects Wendy). No `anthropic_key`-style carve-out needed; this is a financial-write restriction, not a secret.
- **Non-overlapping write planes (C-4 — the ledger's scope guard):** `record_holding_event` **rejects the eligible nine** with a verbatim, staging-matched typed error. Enforcement is two-layer: (1) FK `obligation_key → goal_registry(goal_id)` (identity home; no new registry object); (2) an **in-RPC holding/excluded-set membership check** — v1 the set is exactly `{wewe_rccl, wewe_dcl}`; an eligible-nine goal (e.g. `adam_ira`, `alaska`) → typed reject. Symmetric to Option B rejecting excluded goals. **No obligation is writable through both planes; no double counting** between snapshot progress and ledger basis.
- **Browser-visible actions:** read composition/held/released; owner may initiate `payout_authorized` via an **authenticated owner REST call**. **Real `payout_executed` sittings = authenticated owner REST calls (RG-3 runbook), NOT SQL-editor writes** (C-5). **SQL editor = read/verification only.** **Service role = break-glass DR only** (out-of-band, separately authorized + evidenced; restore-runbook).
- **Prohibited direct writes:** any REST write to `holding_events`; any snapshot/reconciliation write; any SQL-editor/null-auth holding-event write (fails the owner gate by design).
- **Required revokes (staging + prod DDL package):** `REVOKE INSERT,UPDATE,DELETE ON holding_events FROM anon, authenticated`; `REVOKE ALL ON holding_events FROM PUBLIC`; anon EXECUTE on the RPC = false. New table uses conforming `can_write_financials()`/owner policies — **never anon** (standing law).

---

## 8. Invariants and monotonicity

| Invariant | Rule |
|---|---|
| Cumulative funded progress | **Monotonic non-decrease** (snapshot plane, unchanged; enforced by the wrapper/Option B, NOT re-hardened here) |
| Basis | `frozen opening basis (wewe_* row) + net basis_adjustments` — **may only rise** via owner-only, note-required `basis_adjustment` (C-1); a `reversal` of a `basis_adjustment` adjusts net |
| Net released | May move **down** only via an explicit `reversal` event (ledger stays append-only; net is a fold) |
| Current held | `basis − net released` — **may reverse** (down on payout, up on reversal/basis-adjustment); **no-negative-held** below |
| No-negative-held / no-release-beyond-basis | `net released ≤ basis` per obligation — **over-release is a HARD reject with no override flag** (C-1); the sanctioned valve is a prior-or-same-operation `basis_adjustment` |
| Over-release check is **aggregate + order-independent** (C-2) | the guard compares Σ(releases) to Σ(basis) at commit — **not** event-by-event — so a **retroactive `effective_at` insertion can never create an invalid final state**; state this property explicitly in the spec |
| Duplicate-event control | `idempotency_key UNIQUE` (same-key retry idempotent) **plus** the `duplicate_suspect` read-model flag for distinct-key re-entry (C-2 §4) |
| Event sequence | `payout_executed` allowed with/without prior `payout_authorized`; when `effective_at` materially precedes `created_at` the read-model labels **"retroactive entry"** (not "execution without intent", B-5); a `reversal` **must** reference an existing `related_event_id` (C-3) |
| `effective_at` vs `created_at` (C-2; **`timestamptz`**) | **`effective_at timestamptz NOT NULL`** = the actual **effective timestamp** of the financial event (operator-supplied; RPC defaults `now()` when omitted) — drives closed-week assignment, statement attestation, as-of composition, retroactive entry, degradation replay. **`created_at timestamptz`** (server `now()`) = the durable DB-recording timestamp — drives audit chronology, retry/idempotency, divergence. **The effective financial event is NOT reduced to a calendar date.** Actor `created_by_user_id = auth.uid()` (nullable under the SQL-editor read path only — never a write path, C-5). Fold order **`(effective_at, created_at, id)`** (deterministic) |
| Closed-week assignment (C-2) | derived **from `effective_at`** using the **model's governing timezone and week-boundary rules** — an event's closed week = the model week whose \[start,end) contains `effective_at` in the governing tz; a boundary timestamp resolves by the model's `<end` convention. Two same-day events order by `(effective_at, created_at, id)` |
| Reversal linkage integrity (C-3) | `UNIQUE(related_event_id) WHERE related_event_id IS NOT NULL` (each event reversed **at most once**); **RPC/trigger-enforced** (cross-row, CHECK can't see other rows): target exists · **same `obligation_key`** · target type ∈ {`basis_adjustment`,`payout_authorized`,`payout_executed`} (**never a `reversal`** — no reversal-of-reversal) · **reversal amount = target amount** (full-annul; value changes use the correction workflow = reversal + replacement) · **no self-reference** → **no double reversal, no reversal-of-reversal, no cross-obligation reversal, no partial-amount reversal** |
| Terminology (one contract) | **`reversal`** = fully annul a specific prior event (money didn't move / wrong event). **Correction workflow** = `reversal` + a new **replacement** event (own `idempotency_key`; optional non-financial `correlation_id`) — **not** an event type. **Supersession** = a target's fold effect removed by its reversal. Never edit/delete a row |
| Cross-week / cross-obligation | events are **obligation + `effective_at` (timestamptz) keyed, NOT `week_num`-keyed** → rollover-neutral; a later-recorded release folds into the closed week of its `effective_at`; no cross-obligation linkage |

---

## 9. Migration and historical-state treatment (schema described; NO file created)

**Draft table structure (illustrative — the spec locks final names/types):**

```
holding_events   (final per C-1/C-2/C-3/C-4; four financial event types)
  id                 uuid PK default gen_random_uuid()
  obligation_key     text NOT NULL REFERENCES goal_registry(goal_id)   -- C-4 (+ in-RPC holding-set membership: {wewe_rccl,wewe_dcl})
  event_type         text NOT NULL       -- CHECK IN ('basis_adjustment','payout_authorized','payout_executed','reversal')  -- C-1 (no 'correction')
  amount_cents       bigint NOT NULL      -- positive magnitude; effect = f(event_type) (B-3; signed amounts rejected)
  effective_at       timestamptz NOT NULL -- C-2: actual effective TIMESTAMP of the financial event (operator-supplied; RPC defaults now())
  idempotency_key    text NOT NULL UNIQUE
  related_event_id   uuid NULL REFERENCES holding_events(id)           -- required iff event_type='reversal'
  correlation_id     text NULL            -- optional NON-FINANCIAL link (correction workflow: reversal + replacement); never affects folding
  account_key        text NULL REFERENCES accounts(key)               -- AMEX Savings hold; NOT NULL when event_type='payout_executed' (RPC/trigger-enforced)
  note               text NOT NULL        -- note required for owner events (basis_adjustment/reversal + replacement); evidence discipline
  evidence_ref       text NULL            -- statement/worksheet pointer (optional)
  source             text NOT NULL default 'holding_event'
  created_by_user_id uuid NULL default auth.uid() REFERENCES auth.users(id)   -- NULL only under the SQL-editor READ path; writes require auth.uid() (C-5)
  created_at         timestamptz NOT NULL default now()                -- durable DB-recording timestamp
  CONSTRAINT chk_he_type   CHECK (event_type IN ('basis_adjustment','payout_authorized','payout_executed','reversal'))
  CONSTRAINT chk_he_amount CHECK (amount_cents > 0)
  CONSTRAINT chk_he_link   CHECK ((event_type = 'reversal') = (related_event_id IS NOT NULL))
  CONSTRAINT uq_he_reversal_target UNIQUE (related_event_id)           -- C-3 (partial: WHERE related_event_id IS NOT NULL) — reversed at most once
INDEX (obligation_key, effective_at)   -- C-2, alongside (obligation_key, created_at)
-- immutable-audit trigger: BEFORE UPDATE/DELETE -> RAISE (append-only), mirrors outflow_events
-- RPC/trigger cross-row checks (CHECK cannot see other rows): reversal target exists,
--   same obligation_key, target type in {basis_adjustment,payout_authorized,payout_executed}
--   (NEVER reversal -> no reversal-of-reversal), reversal amount = target amount, no self-reference;
--   holding-set membership; account_key NOT NULL for payout_executed; over-release aggregate check.
--   closed-week assignment derived from effective_at via the model's governing tz + week-boundary rules.
```
- **Projection `holding_state` (view):** per obligation → `basis = anchor(wewe_* row) + net_basis_adjustments`, `net_released = Σ executed − Σ reversed`, **`held = basis − net_released`**, `authorized_pending`, `flags` (`retroactive_entry`, `duplicate_suspect`, `over_release_blocked`, `residual_review`). Cents↔`numeric(12,2)` conversion is exact at 2dp — state the ×100 boundary once in the spec.
- **Enums/CHECKs:** **four-value** `event_type` CHECK (C-1; no `correction`); amount > 0 (B-3); link-required iff `reversal`; **UNIQUE `related_event_id`** (C-3, reversed-at-most-once); UNIQUE `idempotency_key`.
- **Keys/FKs:** PK `id`; **FK `obligation_key`→`goal_registry(goal_id)`** (C-4; identity home, no new registry object — B-4); FK `account_key`→`accounts`, `related_event_id`→self, `created_by_user_id`→`auth.users`. `correlation_id` is a **non-financial** free identifier (correction-workflow linkage), no FK. **No FK to `goal_funding_snapshots`** (logical join by `obligation_key==goal_id`; avoids coupling the frozen surface).
- **Timestamps/actor/source:** **`effective_at timestamptz`** (actual effective timestamp of the financial event; not reduced to a date), **`created_at timestamptz`** (durable DB-recording timestamp), `created_by_user_id` (actor — present on every write; NULL is the read-only SQL-editor path only), `source` literal.
- **Event identity / idempotency:** `id` (surrogate) + `idempotency_key` (natural, UNIQUE; convention `obligation|type|effective_at|magnitude|seq`).
- **Migration order:** (1) table + CHECKs + UNIQUE + indexes; (2) immutable-audit trigger; (3) `record_holding_event` RPC (`SECURITY DEFINER`, owner-gated, holding-set membership, cross-row linkage checks, aggregate over-release, atomic basis+release option); (4) `holding_state` view; (5) grants/revokes (staging-first; **inert in prod until its own activation**). Preflight/validation/rollback per every prior phase.
- **Backfill / seed / historical treatment (corrected):** **no snapshot row is rewritten; no fabricated historical location evidence.** The `wewe_rccl`/`wewe_dcl` Week-5 `correction` rows remain the **frozen opening basis** (historical cumulative progress, correct as-of Week 5). **Opening state = the retained rows; NO ledger backfill of opening events** (opening/migration events for RCCL/DCL are explicit non-events). **A `basis_adjustment` is required** only when the excluded obligation's basis must change *after* the frozen anchor (funding increase, or a real payout exceeding the frozen basis — record the basis fact first/atomically). **Retroactive RCCL/DCL facts** are represented as `payout_executed` (and, if needed, `basis_adjustment`) events carrying the **real `effective_at` timestamp** (actual cash-movement time) with `created_at` = recording time — never a fabricated timestamp; closed-week assignment follows from `effective_at` under the governing tz. **Note/evidence:** every migrated/replayed or owner event carries a required `note` + optional `evidence_ref` (statement/worksheet pointer); a correction workflow links its reversal + replacement via `correlation_id` or the note; values stay in the local worksheet (balance-free commits). **Terminal disposition of the `wewe_*` rows:** retained, unchanged, as the basis; "still held vs paid out" is answered by the ledger — no permanent fossil, **no terminal marker minted** (the `terminal` state stays advisory, Q6).
- **Rollback boundaries:** ungrant → drop view → drop RPC → drop trigger → drop table (only while empty / pre-activation); post-activation, data is preserved and a **reversal (+ replacement) event** is used instead of a drop (§12).

---

## 10. AMEX Savings and Account Composition interaction

- **Modeled AMEX Savings balance:** 1B introduces a **holding drawdown** at the engine seam — a `payout_executed` reduces the modeled *held* portion of AMEX Savings; total modeled AMEX cash is affected only insofar as the release reflects real cash leaving. Engine touch is a **1A.5-style carve-out at the integration seam** (named call sites), **not** a `runModel` internal rewrite — under a runModel freeze exception (Adam).
- **Held amount by obligation:** = `holding_state.held` = **frozen opening basis + net basis adjustments − net executed releases** (C-1), per obligation.
- **Release timing:** ledger `created_at` of the `payout_executed` leg; "Transfers to execute" reads `payout_authorized` not yet executed.
- **Reconciliation:** the executed sum per obligation is **attested against the AMEX statement** at close (statement attestation, Monthly Close §3.3) — the release is **not** a closeout write.
- **Interest/timing residual:** flows to the Account Composition rider's **"Unattributed (timing/interest)"** line (§18 of the roadmap) — the same SA8 "expected under-attribution" class; **never plugged**.
- **Two-sided invariant:** 1B makes the AMEX holding invariant **two-sided-able** by giving releases a durable exit record; the *hardening* to a two-sided hard gate is **1B-S4** (§13).
- **Account Composition Visibility Rider (§18):** 1B is precisely what makes the AMEX card's **durable** lines real — `wewe_*` holds/releases become durable (post-1B). Before 1B they have no exit record; after 1B the rider shows `durable` held + released per obligation, IRA/529 sweep stays `modeled`, residual = "Unattributed (timing/interest)". **1B introduces NO second Available/Free cash calculation** — it produces *composition/held/released* facts only; availability stays the 5F-1 CAE / 5G-3's job. (§14 details exactly what becomes durable.)

---

## 11. Staging validation plan (staging-first; NO execution here)

Fixtures on `herndon-fos-staging` (`pkwotgqivgaapwuqgwqb`), balance-free synthetic magnitudes; project-ref + `app_environment` guard on every mutating block (Gate-2 discipline). Matrix (each with whole-state fingerprint + integrity asserts):

1. **Fixture setup** — synthetic `wewe_*` progress snapshots + AMEX account fixture; owner/Wendy staging identities.
2. **Happy path — authorize→execute** — `payout_authorized` then `payout_executed`; `holding_state` reflects held→released.
3. **Partial payout** — execute < held basis; `held` positive; flags clean.
4. **Full payout** — execute == held basis; `full_payout`; no over-release.
5. **Reversal** — reverse an executed event; `held` restored; net released decreases; append-only preserved.
6. **Correction** — supersede a wrong value; `related_event_id` set; prior row intact.
7. **Duplicate (idempotency)** — same `idempotency_key` → returns existing id, no second row.
8. **Unauthorized caller** — non-owner (Wendy) → `42501`; anon → 401/42501.
9. **Wrong role** — writer/`household_admin` write attempt → `42501`.
10. **Stale state** — execute against an obligation whose basis moved; read-model consistency; no phantom write.
11. **Out-of-order event** — `execute` before any `authorize` → allowed but **flagged** (execution-without-intent); `reversal` with missing `related_event_id` → reject.
12. **Over-release** — `net released` would exceed **basis** → hard `over-release` reject verbatim (no override flag).
13. **Cross-week behavior** — events across two model weeks; rollover-neutral (no `week_num` key); fold by `effective_at` correct.
14. **Account-composition read model** — `holding_state` feeds a rider-shaped read; durable (basis+adjustments−releases) vs modeled lines; residual math balances.
15. **Cleanup** — teardown synthetic events; ungrant to inert; `GATE TEARDOWN PASS`.
16. **Fingerprint validation** — deployed RPC/table definitions byte-identical to approved baselines (md5), like the 5G-1D Gate-2/validation.
17. **Production-parity checks** — staging schema == prod target; grant matrix before/after matches the approved package.

**RG-1 required test additions (C-1…C-5; a Code session must include these):**
- **T-A Basis adjustment increases held basis** — `basis_adjustment` then payout to the new basis succeeds.
- **T-B Release above frozen basis fails without adjustment** — `payout_executed > basis` with no adjustment → hard over-release reject.
- **T-C Adjustment + valid release under the atomicity contract** — atomic single-call basis+release commits both rows; over-release aggregate check passes at commit.
- **T-D Retroactive `effective_at` folds into the correct closed week** — RCCL entry with an August `effective_at` recorded in September folds at a Week-8 pinning; close-attestation binds to the August statement; `retroactive_entry` flag set; the aggregate over-release check proven **order-independent** (retro-insert cannot create an invalid final state).
- **T-E SQL-editor / null-auth owner call FAILS** — RPC via SQL-editor context (`auth.uid()` NULL) → `42501` **as a passing test** (proves the C-5 contract); the authenticated owner REST sitting succeeds with actor stamped.
- **T-F Eligible-nine goal rejected** — `record_holding_event('alaska', …)` / `('adam_ira', …)` → verbatim scope reject (C-4; the single most important new negative test).
- **T-G Double reversal fails** — second reversal of one target → UNIQUE(`related_event_id`) reject.
- **T-H Cross-obligation / reversal-of-reversal / self-reference / partial-amount reversal all fail** — C-3 linkage negatives.
- **T-I Duplicate-suspect** — same obligation+type+magnitude+`effective_at` under two distinct keys → both persist, `duplicate_suspect` flag raised (documents the idempotency boundary §11 previously missed).
- **T-J DR replay** — restore staging from dump; replay/verify the type-aware fold identical (validates §13's replay claim end-to-end).
- **T-K `effective_at timestamptz` folding contract (C-2):** (a) **same-day ordered events** — two events same `effective_at` date, different times → order by `(effective_at, created_at, id)`, deterministic; (b) **week-boundary events** — `effective_at` at the model week `[start,end)` boundary resolves to the correct week under the `<end` rule; (c) **timezone normalization** — the same instant supplied in different offsets folds into the same closed week (governing tz applied); (d) **future timestamp** — `effective_at` in the future → allowed but flagged / validated per spec rule; (e) **retroactive timestamp** — past `effective_at`, later `created_at` → `retroactive_entry`; (f) **same-day execution + reversal** — `payout_executed` then `reversal` same day fold net-zero deterministically; (g) **deterministic fold** — shuffling insertion order yields identical `holding_state` (fold keyed on `(effective_at, created_at, id)`, not insertion order).
- **T-L Correction workflow (reversal + replacement):** reverse a wrong `payout_executed`, then append a replacement `payout_executed` with corrected facts + its own `idempotency_key` (+ `correlation_id`) → fold reflects only the replacement; a **second** `correction` amount-bearing event type does **not** exist (attempting to insert `event_type='correction'` → CHECK reject).
- Plus refreshed **partial/full payout**, **retry/idempotency**, **Account Composition read-model**, and **graceful-degradation replay** tests against the corrected doctrine.

---

## 12. Real-caller security plan

**Two layers (both required), Gate-2 style:**
- **SQL role-impersonation** (`SET LOCAL ROLE` + `request.jwt.claims`, rolled-back txn): owner writes ALLOW; `household_admin` write DENY (`42501`); anon DENY; exact grants asserted (no INSERT/UPDATE/DELETE to authenticated on the table; EXECUTE only on the RPC; anon EXECUTE false); append-only + immutable-audit proven structurally.
- **Real Auth→JWT→PostgREST** (throwaway script, uncommitted; tokens local-only): **owner** RPC call succeeds; **Wendy/household_admin** RPC → `42501`; **viewer/unauthorized** read `[]`/write 403; **anon** 401; **expired token** rejected; **malformed request** (bad body / wrong types) rejected with typed error; **direct REST table write** to `/rest/v1/holding_events` → 403/42501 (prohibited path proven closed); **governed RPC call** succeeds owner-only; **revoked legacy path** (no snapshot/recon regression — old surfaces still revoked); **service-role/emergency path** proven owner-equivalent and out-of-band (not a client route).

All expected reject phrases matched verbatim; no household values; all tokens/UUIDs local-only (`~/.gate*` pattern, outside the repo).

---

## 13. Rollback and recovery plan

- **Pre-migration backup:** custom-format public-schema `pg_dump` (DR floor) before the prod DDL sitting; SHA-256; `pg_restore --list`; encrypted off-device (DR-1 cadence + pre-migration).
- **Migration rollback:** while pre-activation/empty — ungrant → drop view/RPC/trigger/table (exact-restore script); the table is inert (ungranted) before any grant, so a failed migration leaves prod behavior unchanged.
- **Event rollback vs reversal:** **post-activation, never drop data.** A wrong event is annulled by a `reversal` (and, for a value fix, a replacement event) — append-only, not a DELETE. The only "rollback" post-activation is grant rollback to inert.
- **Safe failure posture:** at every stop the prior state is intact (append-only); a partially-run sitting leaves either no new events or only fully-committed events (each RPC call is atomic).
- **Partial activation:** table+RPC deployed inert (no grant) is behavior-neutral (REST → 404/PGRST202), exactly like the 5G-1D Slice-6 inert deploy; the grant is a separate gated step.
- **Grant rollback / browser rollback:** grant rollback A (RPC → inert); browser revert (revert the merge; redeploy prior build) — the read-only surfaces degrade gracefully (composition card hides).
- **Data cleanup rules / never-rerun SQL:** the retroactive-RCCL seed and any one-shot are **plain INSERT via the RPC with an `idempotency_key`** — a rerun is idempotent (returns existing id), so unlike the 2.1 correction it is **not** a never-rerun hazard; still, each production sitting is logged.
- **Restore-runbook interactions:** `holding_events` is in the public-schema dump (unlike `auth`), so a restore replays it; the projection rebuilds deterministically; AF-1 auth re-link still applies to authorize the owner.
- **Production execution ledger evidence:** append one line per production sitting to `docs/execution-ledger.md` (date, file, commit, evidence, rerunnable=yes-idempotent).

---

## 14. Account Composition rider interaction (what 1B makes durable)

| Element | After 1B | Evidence class |
|---|---|---|
| AMEX Savings composition | RCCL/DCL become **durable** lines — derived **`held = frozen basis + net basis_adjustments − net executed releases`** (C-1) | **durable** (ledger basis + release events) |
| RCCL/DCL current held amounts | `holding_state.held` per obligation (basis-corrected formula) | **durable** |
| Release & payout history | full `basis_adjustment`/`payout_authorized`/`payout_executed`/`reversal` timeline per obligation, `effective_at`-timestamped (corrections appear as reversal + replacement) | **durable** |
| Residual | interest/timing/uncleared → "Unattributed (timing/interest)", near-zero, review-flag on breach; interest is **excluded from held** (belongs to residual, never an obligation) | residual (unchanged) |
| IRA/529 sweep accumulation | still **modeled** (no durable deployment record — `_amxHold` mechanics) | **modeled** (unchanged) |
| Plan set-asides (Mint etc.) | still waits for **5G-2** (`outflow_events` additive component) | deferred to 5G-2 |
| Truist Savings / Checking | unaffected by 1B — Truist Savings stays all-`modeled` (rider, needs no 1B); Checking stays 5G-3 | deferred (5G-2/5G-3) |

**Confirmation:** 1B makes only the **AMEX RCCL/DCL held/released** durable, via `basis + adjustments − releases`. Everything else the rider shows stays modeled or deferred. **No second Available/Free number is introduced.**

---

## 15. Acceptance criteria

**Phase-level (1B complete when):** DCL payout recorded through `record_holding_event` with reconciled AMEX statement attestation; RCCL retroactively recorded; the accepted AMEX-offset variance entry **expired** from the register; the `wewe_*` rows have their documented terminal disposition; **1B-S4 is unblocked** with a queryable release state; **no snapshot-layer grant weakened** and wrapper/Option B contracts **byte-unchanged**; static + e2e green; golden masters unchanged unless an approved engine-output change was recaptured.

**Slice-level:**
- **Schema accepted** — table/CHECKs/indexes/trigger/view reviewed; owner-pinned; inert deploy green (REST → 404 pre-grant).
- **Grants & RLS proven** — real-caller matrix (§12) green; owner-only writes; anon/Wendy DENY; direct table write closed.
- **Idempotency proven** — duplicate `idempotency_key` returns existing id.
- **Reversal + correction-workflow proven** — reversal restores held; a value fix = reversal + replacement (no `correction` event type); append-only intact; `effective_at`-timestamp folding deterministic (same-day, week-boundary, tz).
- **Historical state handled** — retroactive RCCL entered; `wewe_*` basis unchanged.
- **No snapshot-surface regression** — G-01…G-08 unchanged; `goal_funding_snapshots` byte/state-identical.
- **AMEX modeled effects reconcile** — held/released fold matches the statement attestation; residual within accepted variance.
- **Account Composition contract supported** — `holding_state` yields the rider's durable AMEX lines.
- **Rollback rehearsed** — inert-deploy + ungrant + (staging) drop rehearsed.
- **Production activation evidence defined** — preflight/validation/rollback + execution-ledger line.
- **1B-S4 complete or explicitly demoted** (§13/§18).

---

## 16. Test strategy

- **Static tests:** RPC/table/trigger presence + shape; grant matrix; a **prohibited-vocabulary/second-availability** static assert on any 1B UI (no Available/Free); read-model derivation unit cases.
- **Unit/contract:** `holding_state` **type-aware** reducer (fold `(effective_at, created_at, id)`, superseded rows excluded) — basis-adjustment/partial/full/reversal/over-release/retroactive/duplicate-suspect cases.
- **SQL behavioral:** the §11 staging matrix **including the RG-1 additions T-A…T-J** (basis flows, effective-dating/order-independence, linkage integrity, eligible-goal reject, null-auth reject, duplicate-suspect, DR replay) with fingerprints.
- **API caller:** the §12 real-caller matrix (owner/Wendy/viewer/anon/expired/malformed/direct-REST/governed-RPC/revoked-legacy/service-role) **plus T-E (SQL-editor null-auth owner call → `42501` as a passing test)** and **T-F (eligible-nine reject)**.
- **Browser/E2E:** held→released UI transition; owner authorize flow; Wendy read-only; degraded state on load failure; `5G1B-*` tags; e2e runtime budgeted (the full `node e2e.js` gate).
- **Golden-master expectations:** recapture **only if** the engine seam changes weekly outputs, **with Adam approval** (never edit expected outputs to pass). Capture 1B's masters **once, on the D7-corrected Diablos/GLP baseline** (roadmap §4 prerequisite).
- **Migration tests:** preflight/validation asserts; inert-deploy REST 404; owner-pin.
- **Rollback tests:** ungrant-to-inert; staging drop-and-restore.
- **Production smoke:** post-grant REST reachability; one owner `payout_authorized` dry event on staging-parity; live verification balance-free.
- **Regression scope:** static + full e2e green (current baseline static 1507 / e2e 148 as the floor); 5G-1D closeout suites unaffected.
- **Test-data cleanup:** synthetic events torn down; staging returned to baseline; local-only tokens/values.

---

## 17. Implementation and commit sequence (future Code session; separable/reversible commits)

1. **Architecture/spec approval** (this doc → ChatGPT adversarial + §4.1/§4 conformance + Adam; optional Fable ≤ Jul 19).
2. **Migration/schema** — `holding_events` + CHECKs + indexes + trigger + `holding_state` view (staging first). *Separable commit; reversible (drop while empty).*
3. **RLS/grants/RPC** — `record_holding_event` (`SECURITY DEFINER`, owner-gated) + revokes + grants package (staging). *Separable; reversible (ungrant).*
4. **Server/read-model logic** — `holding_state` derivation + any RPC helpers. *Separable.*
5. **Browser integration** — held/released UI, owner authorize flow, degraded state; engine seam carve-out under the freeze exception. *Separable; branch-held; reversible (revert merge).*
6. **Staging fixture** — §11 matrix. *Separable.*
7. **Security tests** — §12 real-caller matrix. *Separable.*
8. **Failure injection** — over-release/out-of-order/duplicate/stale. *Separable.*
9. **Activation package** — preflight/validation/rollback + operator runbook (RG-3), 5G-1D-style. *Separable.*
10. **Production execution** — inert deploy → grant → retroactive RCCL → (later) DCL live; each an owner sitting; execution-ledger line. *Reversible to inert.*
11. **Closeout/status documentation** — closeout doc + CODEX_STATUS + decision-log; 1B-S4 disposition.

**Separability rule:** schema, grants/RPC, and browser are **independent reversible commits** (inert deploy proves this); production grant and the DCL live entry are **distinct gated sittings**, never bundled.

---

## 18. Graceful-degradation plan (if 1B is not complete before the DCL window)

- **What remains operational:** weekly closeouts (wrapper), Monthly Close, 5G-2/rollover chain — all independent of 1B.
- **What remains advisory:** the AMEX holding invariant stays **one-sided/advisory** (its current state); the Account Composition rider ships **without** the durable AMEX release lines (durable lines require 1B) — it either defers the AMEX card or shows `wewe_*` as `modeled` with a large residual, honestly labeled.
- **How the DCL payout is handled:** the real DCL cash movement is recorded as a **standing accepted-variance register entry** (the existing posture) + a **balance-free manual note** in the close worksheet; **not** improvised into snapshots, WD, or a hand-edit. The AMEX offset variance simply does not expire until 1B lands.
- **How release history is documented:** a dated manual note (obligation, authorized/executed, **the real cash date**, statement reference) in the close evidence, to be **replayed as ledger events** once 1B is live — **this replay REQUIRES C-2's `effective_at`** (without it the post-hoc DCL replay would fabricate a recording-date for October cash); idempotent by `idempotency_key`.
- **What must not be improvised:** no snapshot rewrite; no `wewe_*` edit; no WD/effectiveWD injection; no direct table write; no ad-hoc RPC.
- **When implementation resumes:** first WIP=1 slot after the DCL slip is absorbed; 1B stays the calendar-forced item (its bound just passed, so it becomes highest-priority remediation, still gated).
- **Whether 1B-S4 sheds first:** **yes** — 1B-S4 (invariant hardening) demotes to a separate fast-follow (SR-2 valve); the advisory posture is graceful over winter. Core 1B (the ledger + releases) does **not** shed — it is what makes the DCL history durable.
- **Required decision + evidence record:** a dated graceful-miss record (variance entry, manual DCL note, resume trigger, 1B-S4 demotion), committed balance-free; decision-log line.

---

## 19. Decision register (B-1 … B-12) — all resolved; none open

*Two classes: **[IMPLEMENTATION DETAIL — RG-1 RESOLVED]** = settled by the Fable RG-1 review; confirm at spec approval, no separate ruling. **[APPROVED — ADAM]** = owner-approved 2026-07-14; several carry a **future activation gate** (the approval is the policy; the gated action executes at build/DCL). **No B-decision remains an open/unresolved Adam decision.***

| # | Decision | Class | Resolution | Future gate |
|---|---|---|---|---|
| B-1 | Write surface: one governed RPC vs per-type RPCs | IMPLEMENTATION — RG-1 | **One RPC + `event_type`** (split later only on a materially different signature) | — |
| B-2 | Design: append-only ledger + projection vs current-state table | IMPLEMENTATION — RG-1 | **Append-only ledger (Branch b)** — Branch (a) not reopened | — |
| B-3 | `amount_cents` convention | IMPLEMENTATION — RG-1 | **Positive magnitude + type-effect; signed rejected** | — |
| B-4 | Reuse `wewe_*` `goal_id` as `obligation_key` | IMPLEMENTATION — RG-1 | **Reuse + C-4 FK + holding-set membership** (no new registry object) | — |
| B-5 | `payout_executed` without prior intent | IMPLEMENTATION — RG-1 | **Allow + label "retroactive entry"** when `effective_at` precedes `created_at` | — |
| B-6 | runModel freeze exception for the drawdown seam | **APPROVED — ADAM** | **Approved: narrow model-freeze exception limited to the approved seam, verified by golden masters** | seam verified by golden masters at build |
| B-7 | 1B-S4 invariant hardening + demote valve | **APPROVED — ADAM** | **Approved: 1B-S4 in-scope with the SR-2 demotion valve**; core ledger never sheds | demote decision only if DCL pressed |
| B-8 | Golden-master recapture if the seam changes outputs | **APPROVED — ADAM** | **Approved: recapture ONLY with an explicit expected-effect record + Adam review** (never edit expected outputs to pass) | the recapture itself, at build |
| B-9 | Wendy read access (write always denied) | IMPLEMENTATION — RG-1 | **Read yes, write no** | — |
| B-10 | Production execution path (C-5) | **APPROVED — ADAM** | **Approved: authenticated owner REST/RPC is the normal path; SQL editor read-only; service role break-glass only** | DCL live sitting (RG-3 runbook) |
| **B-11** | basis-adjustment contract (C-1) | **APPROVED — ADAM** | **Approved: owner-only, note-required `basis_adjustment`; over-release is a hard reject with NO override** | — |
| **B-12** | `effective_at` + retroactive-entry contract (C-2) | **APPROVED — ADAM** | **Approved: `effective_at timestamptz` + `created_at`, with governed retroactive-entry rules** (closed-week from `effective_at` via governing tz; fold `(effective_at, created_at, id)`; aggregate order-independent over-release) | — |

---

## 20. Fable-baseline conformance matrix (roadmap §4 / §4.1 + RG-1 C-corrections)

| Requirement | This package | Conforms |
|---|---|---|
| Release-event semantics; payout ≠ reset of cumulative progress | §4 two-plane model; §8 | ✓ |
| Write surface = explicit branch (a) vs (b), with grant matrix before/after | §1/§5/§6 → **branch (b)**; §7 matrix; snapshot grants unchanged | ✓ |
| Eligible-set/monotonicity boundary; excluded goals never enter the nine | §7; §8 (non-decrease stays wrapper policy, not a table constraint) | ✓ |
| Model/engine interaction as a runModel freeze exception at named seam | §10; B-6 | ✓ |
| Reconciliation & close: releases are NOT closeout writes; variance expiry; statement attestation | §7; §10; §14 | ✓ |
| Corrections: reversing event, never edit; reopen = none; Gate E posture | §5; §8; §12 | ✓ |
| Operational controls: owner-only, RLS/grants, balance-free evidence, RCCL/DCL runbook | §6/§7; §13; §17 | ✓ |
| Downstream contracts: 1B-S4 consumes queryable release state; 5G-3 reads Spoken-For for AMEX | §13; §10/§14 | ✓ |
| Prerequisites: 5G-1D complete + Phase-2 revokes; D7 baseline; DR-1 closed; freeze-exception; spec cleared | §3/§16; B-6/B-8 | ✓ |
| Non-goals: no goal CRUD, no 4a unification, no L2 conflation, no anchor change, no 5G-2 build | §3 | ✓ |
| Review gates RG-1/RG-2/RG-3; sizing (schema+grant+engine+ops, three gates, not "tightly like 1A.5") | §11/§12/§17; §1 | ✓ |
| Rollover-neutral (not in AF-2 inventory) | §8/§9 (obligation + `effective_at` keyed) | ✓ |
| **C-1 basis-side event (`basis_adjustment`); held = basis + adjustments − releases; over-release hard-reject, no override** | §1/§4/§8/§9; B-11 | ✓ **folded** |
| **C-2 `effective_at timestamptz` distinct from `created_at`; closed-week from `effective_at` via governing tz; fold `(effective_at, created_at, id)`; over-release aggregate + order-independent** | §4/§8/§9; B-12 | ✓ **folded** |
| **Final taxonomy (4 types): `correction` removed; corrections = reversal + replacement** | §4/§5/§8/§9; §11 T-L | ✓ **folded** |
| **C-3 reversal linkage integrity — UNIQUE(related_event_id), same-obligation, target-type limited, full-annul, no self-ref/double/cross** | §8/§9; §11 T-G/T-H | ✓ **folded** |
| **C-4 non-overlapping write planes — RPC rejects the eligible nine (FK + membership); no double counting** | §4/§7/§8/§9; §11 T-F | ✓ **folded** |
| **C-5 production path — authenticated owner REST call, not SQL-editor; service-role = break-glass DR only** | §6/§7; B-10; §11 T-E | ✓ **folded** |

---

## 21. Fable RG-1 review — status & responses

**RG-1 verdict: ADOPT WITH CHANGES — received 2026-07-14.** C-1…C-5 are **folded** into this document (above). B-11/B-12 added; B-10 amended (§19). **Package status: implementation-ready ONLY after these corrections are incorporated (done) AND Adam approves (spec approval).** Fable access ends Jul 19 — no further Fable pass is required; the twelve review questions are answered below by the review itself.

*(Q1)* Branch (b) dominates in every case examined incl. restore (ledger in the public-schema dump, deterministic replay) — **(a) not reopened.** *(Q2)* Two-plane split correct, **corrected**: held = **basis (frozen anchor + net `basis_adjustment`) − net released** (C-1); no stored current-held. *(Q3)* One RPC + `event_type` confirmed (B-1); no authz/idempotency risk. *(Q4)* Separate intent/execution correct; execution-without-intent allowed, labeled **"retroactive entry"** (B-5). *(Q5)* Over-release reference **corrected**: for excluded obligations the basis is the **latest existing snapshot (Week 5) + ledger adjustments**, not "latest closed week"; check is **aggregate + order-independent** (C-2). *(Q6)* `wewe_*` retention + ledger releases **fully retires the fossil problem** — **no terminal marker needed** (`terminal` stays advisory). *(Q7)* Engine seam is a scoped 1A.5 named-call-site carve-out (B-6) — keep it scoped to avoid re-review. *(Q8)* 1B-S4 correctly outside core 1B (demotable, SR-2); core's queryable release state fully unblocks it (B-7). *(Q9)* Rider makes exactly AMEX RCCL/DCL held/released durable; **no second availability number** (§10/§14). *(Q10)* Graceful-miss posture endorsed; **replay requires `effective_at`** (C-2 dependency, §18); 1B-S4 sheds first. *(Q11)* Rollover-neutral confirmed — `effective_at` is a **`timestamptz`**, not `week_num`; nothing added to the AF-2 inventory. *(Q12)* **No hidden dependency** on 5G-2/`outflow_events` or 5G-3 — they stay independent.

**Two final contract corrections (2026-07-14, post-RG-1, Adam-directed):** (1) **`effective_at` is `timestamptz NOT NULL`** (not a calendar date); closed-week assignment is derived from `effective_at` via the model's governing timezone + week-boundary rules; deterministic fold `(effective_at, created_at, id)`; validation/tests for same-day ordering, week boundaries, tz normalization, future + retroactive timestamps, same-day execution+reversal (§8/§9/§11 T-K). (2) **`correction` removed** from the event taxonomy — four financial types (`basis_adjustment`, `payout_authorized`, `payout_executed`, `reversal`); a value correction is a **`reversal` + a new replacement event** (own `idempotency_key`; optional non-financial `correlation_id`), linked in operator evidence; all state folds only from the four types (§4/§5/§8/§9/§11 T-L). **B-6/B-7/B-8/B-10/B-11/B-12 are Adam-approved** (§19); none remains an open decision.

---

*Architecture package only. No implementation code, SQL, migration, RLS, RPC, test, `BUILD_TS`, staging, or production change. Draft SQL is illustrative structure, not a migration file. Adopt/implement per Adam approval, the review chain (§21), and the canonical roadmap sequence (§3.0 #6). 5G-1D remains frozen and authoritative for its own scope; the snapshot grant matrix is not reopened.*
