> **Advisory source review — not implementation authority.** Superseded for sequencing decisions by
> `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md`. Retained for provenance and architectural detail.

# Operating-Model & Control-Design Review — Close, Corrections, Auditability, Recovery

**Date:** 2026-07-12
**Commissioned by:** Adam
**Scope:** plan/specification-level review only. No code was reviewed for implementation quality; no code, schema, or data was changed. 5G-1D is in execution and is treated as **frozen** — nothing here proposes changing its cleared scope; where this review touches 5G-1D it either builds on top of it or feeds its already-open decision points (Gate C, Slice-7 posture register).
**Standing:** advisory review input — **not implementation authority, not a phase spec**. Per the house rule for review artifacts: if anything here conflicts with AGENTS.md, the Do Not Touch list, cleared phase specs, or Wendy-confirmed workflow, those controls win.
**Privacy:** this document contains no household balances. Dollar figures appear only where already present in committed governance docs (e.g., MIN_XFR, the RCCL/DCL holding amounts).

**Grounding:** AGENTS.md; CODEX_STATUS.md; docs/phase-status.md; the 5G-1D stack (plan 2026-07-09, snapshot-correction procedure 2026-07-10, implementation-readiness 2026-07-10, slice-2 proposal, amendments 1–3, Gate-2 runbook); phase-5f-1-spec.md + migration; phase-5f-1.5 audit/Gate-A plan; funding-model-integrity-review-2026-07-08.md; the four 2026-07-10 AMEX Gold register audits; stabilization-roadmap-spec.md; security-brittleness-backlog.md; strategic-roadmap-future-horizons.md; tx-1-candidate.md; 5g-1b defect doc; E1/E2 runbooks and closeout evidence; AI-Context 05/08.

---

## 0. Executive summary

1. **The system's real close unit is the week, and it is already well designed.** Weekly reconciliation is live and proven; 5G-1D (frozen, in execution) adds a genuine two-tier weekly close state machine — *reconciled* vs *fully closed/anchored* — with half-close repair, contiguity enforcement, owner-only reopen, an owner-only correction path, and atomicity. **Month-end close should be a certification layer composed over these weekly primitives, not a second reconciliation machinery.** The roadmap already reserves the slots (5G-1F "July Month-End Close / Audit Minimum Viable Close", 5G-6 "Full Month-End Close / Audit Hardening", 5J event history); they are named but empty. This review is, in effect, the missing design for 5G-1F plus sequencing for 5G-6/5J.
2. **Certify, don't lock.** A hard period lock fights this household's reality (trailing card statements, late-arriving and backdated entries, the standing `posted_date` month-attribution design, and the standing rule against fixing month boundaries by editing `starting_balance`). The right control is an owner certification with a recorded **basis watermark**, plus **divergence detection** when certified data later changes. Corrections stay cheap; certification stays honest.
3. **The proposed 8-state period lifecycle is over-modeled. Use 3 persisted facts + derived readiness.** 5G-1D's own doctrine — states are predicates over data, not stored workflow flags — is correct and should extend upward: OPEN (implicit) → CERTIFIED(v1..vn, append-only records) → REOPENED (explicit owner act) → CERTIFIED(v+1). "Ready for review," "exceptions outstanding," "approved," and "corrected" are all derivable and should never be stored.
4. **The sharpest control asymmetry in the system: the close basis is its weakest table.** `cash_commitments` is the gold standard (server-owned attribution, state machine, terminal immutability, prior-amount capture). `weekly_reconciliations` — the foundation of every close — has **no user attribution, silently overwritable balances (upsert re-save), and a live `deleteRecon` path (direct REST DELETE)**. The 5G-1D write-surface posture register already proposes the fixes (restrict `deleteRecon` for anchored weeks, revoke direct writes); resolving Gate C and executing those revocations is a **mandatory pre-close control**, not an optional hardening.
5. **The biggest near-term risk is not process — it is recovery posture and run-time invisibility.** Backups are event-driven (taken before migrations), not scheduled: the last full restore point predates the E2 anchor seed, the 2.1 correction, the Week-5 reconciliation, and all Register entry since July 9. Restore has never been rehearsed, the Supabase plan has no PITR, there is no backup owner account and no MFA on the owner login — and the SQL editor under that login is the system's god-mode write path. Meanwhile the app can silently lose table loads while showing a green "Model live" badge, and the computed Review-Required verdict is still unrendered. **Quicken is currently the de facto redundant system; its cancellation (after the parallel run) removes the only independent replica.** Recovery readiness must therefore gate Quicken cancellation.
6. **Auditability gap is history, not mutability.** Corrections are in-place value replacements (snapshots, weekly balances, register rows) with prior values preserved only in local evidence artifacts. That is acceptable at current correction volume with the existing evidence discipline, but it does not scale and cannot answer "what changed since close" mechanically. The proportionate ladder: (L1) close evidence packs + certified-aggregate watermarks now, file-based; (L2) one generic `financial_audit_log` trigger table at 5J (pull forward if correction volume grows); (L3) full event ledger only if a later phase genuinely needs it. Do not build L3 speculatively.
7. **First formal month-end close: July 2026, executed file-based (checklist + evidence pack + committed certification record), in the week after the Alaska freeze lifts (from Aug 11), immediately after 5G-1D's post-freeze half-close gap repair.** No new code is required to run it. September's close of the August/September parallel months is the natural Quicken-cancellation instrument.

---

## 1. Ground truth the design must respect

### 1.1 The weekly spine (live + frozen-in-execution)

- One `weekly_reconciliations` row per model week (upsert on `week_num`; no `model_year` column; `recorded_at` server-owned). Captures the five tracked cash accounts + `balance_basis`, alongside the 4-phase cash-commitment flow via `save_reconciliation_with_commitments` (atomic; abort-on-any-failure; conflict-guarded inserts; validated state machine on commitments).
- 5G-1D (frozen) adds: the atomic recon+snapshot wrapper (`save_weekly_closeout_with_snapshots`), the **fully-closed predicate** (reconciled ∧ complete nine-goal snapshot set), branch state machine A–I (legacy weeks 1–4, anchor week 5, new close, idempotent retry, half-close repair, corrupt-state hard stop, contiguity enforcement), `p_mode` strict validation (`normal_closeout` | `approved_reopen`), owner-only reopen limited to the latest completed week, Option B owner-only snapshot correction with nearest-existing monotonicity bounds, GFA01 supervised-adjudication signal, advisory + registry locking for concurrency, and mandatory pre-write exports + external evidence for every exceptional write.
- Doctrine established by 5G-1D that this review extends rather than re-invents: **states are derived predicates, not stored flags; corrections are supervised and evidence-backed; approvals are per-action and never inferred; rollback is break-glass, never a value fix; timestamps are server-owned.**

### 1.2 Three period geometries, zero shared schema

| Geometry | Unit | What it governs | Persistence of "reconciled" |
|---|---|---|---|
| Model weeks (1–31, 2026) | Saturday closeout | 5 cash accounts, commitments, goal snapshots | `weekly_reconciliations` row (+ snapshot set post-5G-1D) |
| Calendar budget months | Month | BLR plan lines, category actuals (Register-fed), income expected | **None** — a month "operates" implicitly when active BLR interval rows cover it |
| Card statement cycles | Statement close date | Register cleared-flag reconciliation per card | **None** — live panel math only; nothing records "account X reconciled to statement Y" |

Two additional labeling hazards compound this: calendar-week vs model-week dual numbering (Cal Wk 27 = model week 5), and the phase-numbering divergence across roadmap docs (`5F-2`/`5G-1..5G-6` mean different things in phase-status.md vs strategic-roadmap-future-horizons.md vs stabilization-roadmap-spec.md). **Any certification record must therefore pin its scope explicitly** (both week numberings, statement IDs, month) rather than rely on ambient labels.

### 1.3 Control asymmetry across the four financial tables

| Table | Attribution | Mutability | History of prior values | Delete |
|---|---|---|---|---|
| `cash_commitments` | created/updated/resolved by+at, server-owned, spoof-proof | Patch-merge via RPC; terminal rows immutable in live save | `original_amount_cents` auto-captured on first amount change | No hard delete (non-goal) |
| `goal_funding_snapshots` | `created_by_user_id`, `created_at`, `updated_at` | In-place natural-key upsert; corrections replace values | **None in DB** — external evidence only | No DELETE policy or grant |
| `weekly_reconciliations` | **None** (only server `recorded_at`) | Fully overwritable by re-save (upsert re-stamps `recorded_at`) | **None** | **Live `deleteRecon` → direct REST DELETE** (restriction proposed, undecided) |
| `transactions` (Register) | `created_at`/`updated_at` documented; no operator attribution in any reviewed spec | Fully editable in UI | **None** | Hard delete in UI (amber confirm) |

The pattern to state plainly: **the newest table is the best-governed; the close basis and the highest-volume table are the least.** "Make the recon row and the register row as accountable as a commitment row" is the cheapest possible framing of the audit roadmap.

### 1.4 Change-time governance is excellent; run-time governance is thin

In place at change time: staging-first DDL, preflight/validation/rollback packages, environment fingerprints and hard-stop guards, run-once discipline (no `ON CONFLICT` on one-shot inserts so reruns fail loudly), sentinel templates vs local value-filled copies, SHA-256 evidence tiers, per-gate explicit approvals, golden-master identity gates, dual test suites gating every push, freeze windows.

Missing at run time: any scheduled backup; any restore rehearsal; any monitoring or alerting; surfacing of per-table load failures (integrity-review risk #4: the green "Model live" badge survives partial load failure); rendering of the computed Review-Required verdict (5F-1 deferral); a recurring data-quality invariant run (the DQ SQL exists only inside migration packages); statement-reconciliation attestations; MFA and a backup owner for the Supabase account whose SQL editor is the god path.

### 1.5 Already-reserved roadmap slots this review fills

- **5G-1F** "July Month-End Close / Audit Minimum Viable Close" — not started, no design. §2–§3 below are the proposed design.
- **5G-1E** "Account Purpose / Holding Bucket Integrity" — promotes the AMEX attribution invariant from one-sided advisory to hard gate (after 5G-1B releases exist).
- **5G-6** "Full Month-End Close / Audit Hardening" and **5J** "Month-end close hardening + minimal goal editing" (also the named home of durable event logging per the 5G-1D CA3 amendment). §4 and §11 sequence what belongs there.

---

## 2. Month-end close — recommended operating model

### 2.1 Design principles

1. **Compose, don't duplicate.** Month-end close consumes weekly closes; it never re-reconciles anything the weekly machine already covers.
2. **Certify, don't lock.** Certification = an owner-signed assertion that a defined scope of data satisfied a defined checklist at a recorded watermark. Data stays correctable afterward; changes to certified scope surface as divergence, they are not prevented. (This respects the standing `posted_date`/5F-3 month-attribution design and the standing rule: *do not solve recurring month-boundary cases by editing `starting_balance`*.)
3. **Readiness is derived; only certifications are stored.**
4. **Evidence before record** (the F-7 doctrine generalized): the close record exists only if its evidence pack exists.
5. **File-based first.** The first two closes run on checklist + committed markdown record (the E2-closeout pattern) with zero new code. Schema/UI come at 5G-6/5J after the ritual has stabilized — the same "manual gated execution first, productize second" pattern the project already uses for migrations.

### 2.2 Close scope and prerequisites (month M)

**Week coverage rule:** M is week-covered when the weekly closeout for the week containing M's last day is **fully closed** (reconciled + complete snapshot set). 5G-1D's contiguity enforcement (branch I) makes this a single check — if the last week is fully closed, all earlier post-anchor weeks are too. Pre-anchor weeks (model 1–4) are recon-only **by design** and certify as such; week 5 is the opening anchor. Illustrative for July 2026: Cal Wks 26–31 ≈ model weeks 4–9; the July close needs model week 9 (Cal Wk 31, week containing Jul 31) fully closed.

**Prerequisites checklist (P1–P9):**

| # | Prerequisite | Concrete check | Mode |
|---|---|---|---|
| P1 | Week coverage | Fully-closed predicate true for the week containing M's last day (contiguity gives the rest) | Automated (SQL/predicate) |
| P2 | Half-closes repaired | No reconciled-but-unsnapshotted post-anchor week ≤ that week (5G-1D branch G detector) | Automated |
| P3 | Statement reconciliation per card | For each card statement closing in M: cleared-set tie-out using the three-total model from the AMEX audits (posted/cleared balance vs statement; uncleared activity enumerated; full-ledger total). Difference = 0 or itemized | Human, attested |
| P4 | Missing-transaction sweep | Statement lines all present in Register (the statement diff is the only real detector today; during Aug–Sep, the Quicken comparison is the second) | Human |
| P5 | Category & data quality | Uncategorized count for M = 0 or dispositioned; BLR/category sync check green (validation-blr-category-sync.sql); split/date conventions spot-checked | Mixed |
| P6 | Budget vs actual review | Per-line Spent vs Budget with over/near dispositions noted; income received-vs-expected reviewed; reimbursables (manual side-channel) tallied | Human |
| P7 | Cash position | Last weekly closeout balances confirmed as basis; unexplained variance = 0 or entered in the accepted-variance register (e.g., the known $1,100 AMEX holding offset until 5G-1B) | Human over automated inputs |
| P8 | Goal funding | Snapshot completeness for M's weeks; any `source='correction'` rows in M listed with evidence refs; monotonicity anomalies explained; AMEX attribution advisory reviewed (hard gate arrives at 5G-1E) | Mixed |
| P9 | Exceptions + backup | No open Blockers (§6); fresh full backup taken after M's last data change, hash recorded | Human + automated check |

### 2.3 Automation boundaries

- **Automate (SQL now, app later):** P1/P2 predicates, snapshot completeness, BLR sync, uncategorized count, duplicate-close refusal, watermark capture, backup-exists check, variance computation.
- **Human review (either operator):** statement tie-outs, budget dispositions, missing-transaction sweep, convention checks, Quicken comparison.
- **Owner approval (Adam) — the fixed list:** the certification itself; reopening; any correction touching certified scope (per the existing 5G-1D owner-path rules); accepted-variance entries outside pre-approved classes; Quicken cancellation.

### 2.4 Certification

One committed markdown record per close — `docs/closes/2026-07-close.md` — following the E2 closeout template exactly: scope pinned (month, Cal/model week range, statement IDs), checklist results, exceptions accepted (with reasons/expiry), **basis watermark** (max `recorded_at` across covered weeks; per-table max `updated_at` + row counts for `transactions`, `goal_funding_snapshots`, `budget_line_rules`, `cash_commitments`; app BUILD_TS), evidence-pack metadata (local filenames, byte sizes, SHA-256 — balance-bearing artifacts stay local per the privacy tiering), certified-by + date. The **certified-aggregates blob** (category totals, per-card cleared balances, goal funded vector) is captured in the local evidence pack; the committed record carries only its hash. This watermark+blob is what later makes "what changed since close?" a diff instead of archaeology.

### 2.5 Reopen and re-close

See §3. Summary: reopen is an explicit owner act with a reason code; it never mutates data by itself; the original certification is never edited; re-close appends certification v(n+1) with a delta summary vs v(n).

### 2.6 First close

July 2026, executed from the checklist file-based, in the Aug 11–17 window (post-freeze, post-Alaska) — deliberately paired with 5G-1D's planned post-freeze activation and sequential half-close gap repair of the freeze-period weeks (~3–4 weeks, per the readiness package). The July close's P2 is exactly that repair. August close ~first week of September; the September close (covering the parallel months) is the recommended **Quicken-cancellation instrument** (§8.3).

---

## 3. Close state model

### 3.1 Challenge to the proposed 8 states

Of open / ready-for-review / exceptions-outstanding / approved / closed / reopened / corrected / re-closed, **five should never be persisted**:

- *ready for review* = readiness predicate over P1–P9 → derive.
- *exceptions outstanding* = open Blockers > 0 → derive.
- *approved* vs *closed* — in a two-person household with a single owner, approval **is** closure; a separate approved state models a segregation of duties that does not exist. Collapse.
- *corrected* = correction records referencing the period exist → derive.
- *re-closed* = certification version > 1 → derive.

Stored workflow states rot and lie; predicates cannot. This is not a simplification for convenience — it is the same doctrine 5G-1D already chose for weeks (fully-closed is a predicate, not a column), and diverging from it at month level would create two philosophies of state in one system.

### 3.2 Recommended machine

**Persisted facts:** (1) append-only **certification records** (period, version, certified_at server-stamped, certified_by, watermark, evidence hashes, accepted exceptions); (2) append-only **reopen records** (period, reopened_at/by, reason code, note); (3) nothing else. Period status derives: no cert → OPEN; latest record is cert → CERTIFIED; latest record is reopen → REOPENED. **DIVERGED** is a derived flag (current recompute ≠ certified watermark/blob), surfaced as an exception — never a stored state and never an automatic reopen.

**Transitions:**

| From → To | Actor | Required evidence | Notes |
|---|---|---|---|
| OPEN → CERTIFIED(v1) | Owner | Checklist + evidence pack + watermark | Requires prior month certified (mirrors weekly contiguity); requires no open Blockers |
| CERTIFIED → REOPENED | Owner | Reason code + note + list of intended corrections | Original cert row untouched |
| REOPENED → CERTIFIED(v+1) | Owner | Correction evidence refs + fresh watermark + delta summary vs prior cert | |
| CERTIFIED → CERTIFIED (dup) | — | — | **Invalid; must fail loudly** (unique (period, version); the run-once/no-ON-CONFLICT discipline) |
| OPEN → REOPENED | — | — | Invalid (nothing to reopen) |
| Any → deleted/edited cert | — | — | Invalid always (append-only; no UPDATE/DELETE — mirror the snapshots table posture) |

**Timestamp behavior:** certified_at/reopened_at are server-owned at schema time (mirroring `recorded_at` doctrine); in file-based mode, the git commit timestamp + in-record date serve. Prior versions' timestamps are never restated.

**Recovery after partial failure:** evidence pack first, certification second. The certification is one atomic append; if it fails after evidence capture, retry is idempotent by (period, version); if evidence capture fails, there is nothing to retry — no record exists. This ordering is deliberate: a certification without evidence must be impossible, evidence without certification is merely unused.

**Interlock with the weekly machine (the critical integration):** month certification never mutates weeks. A weekly `approved_reopen` or an Option A/B snapshot correction that touches a week inside a certified month **must flag month divergence**. Mechanically later (watermark diff); procedurally now: add one line to the 5G-1D correction-evidence checklist — "does this write touch a certified month? If yes, note it in that month's close record." This costs one sentence in an already-mandatory evidence pack.

**File-based interim:** `docs/closes/<YYYY-MM>-close.md` is the certification; reopens append dated sections; git history is the version chain. Promote to schema at 5G-6/5J — the trigger for promotion is Quicken retirement (when the OS becomes the sole system of record) or the third reopen/correction cycle, whichever comes first.

---

## 4. Auditability and historical reconstruction

### 4.1 The seven questions, today vs target

| Question | Today | Target (proportionate) |
|---|---|---|
| What did the system show at close? | Nothing systematic (only migration-time evidence packs) | Certification watermark + certified-aggregates blob per close (L1, file-based) |
| What changed afterward? | Undetectable — corrections are in-place | Divergence diff vs blob (L1); mechanical per-row answer at 5J audit log (L2) |
| Who made the change? | Commitments: fully attributed. Snapshots: `created_by_user_id` (but SQL-editor writes carry **no** auth identity — evidence pack is the only operator record for Option-A corrections). Weekly recon: **nobody recorded**. Register: not documented | Weekly-recon attribution (add columns or log); L2 audit log actor for everything |
| Why was it made? | Snapshot `note`, commitment `resolution_notes`, evidence-pack prose. Weekly recon: nothing | Reason-code vocabulary on corrections/reopens + existing mandatory notes |
| Which records were affected? | Correction spec §11 already mandates affected-row lists — good; keep | Same, plus audit-log rows at L2 |
| Can a prior period be reconstructed? | Balances: yes (weekly rows). Goal attribution: yes post-anchor (snapshots). Register/budget as-of state: **no** (mutable rows, no history) | Certified blob = pragmatic as-of capture per close; true as-of replay only at L3 (don't build until needed) |
| Current vs previously-certified distinguishable? | No | Watermark + divergence flag (L1) |

### 4.2 Challenge: "immutable records" maximalism

Full immutability is the wrong goal here. Weekly re-save is a *feature* (the operating pattern for fixing a same-day entry slip); register editability is Wendy's daily workflow; BLR edits are already structurally history-preserving (interval close + insert). Immutability should apply narrowly to: certifications, the opening anchor (already guarded), evidence artifacts (hash-pinned), and terminal commitment audit fields (already enforced). Everywhere else the gap is **history and attribution, not mutability**.

### 4.3 The proportionate ladder

- **L1 (now, file-tier, no code):** close evidence packs + certified-aggregates blob + watermark; extend the existing correction-evidence discipline (already mandatory for snapshots) to *any* owner-path write touching a certified month; adopt the reason-code vocabulary (suggested: `late_statement`, `entry_error`, `duplicate`, `missed_transaction`, `bank_adjustment`, `model_correction`, `other`+note).
- **L2 (5J, or pulled forward on triggers below):** one generic `financial_audit_log(table_name, row_pk, action, old_row jsonb, new_row jsonb, actor, at)` populated by AFTER triggers on `transactions`, `weekly_reconciliations`, `goal_funding_snapshots`, `budget_line_rules`. Trigger-only writes, no grants, read-only to authenticated. This single table answers who/what/before/after for the whole system at near-zero workflow cost. It is additive but sits on frozen-adjacent tables — staging-first with its own approval gate, after 5G-1D ships. **Pull-forward triggers:** a third owner correction in a quarter, or Quicken cancellation, whichever first. (The security backlog's own criterion for an audit log — "before any financial write capability is shared" — was met on July 1 when Wendy went live; the item is now due, not aspirational.)
- **L3 (only on demonstrated need):** append-only event ledger (the integrity review's Option C, snapshot `release` rows for 5G-1B, custodian sourcing). Do not build speculatively.

---

## 5. Correction and reopen workflows

### 5.1 Disposition matrix

"Regenerate derived records" is mostly free in this architecture — `runModel` and Budget aggregates recompute from source on every run; the only non-regenerable records are **observations** (snapshots, reconciliations — corrected, never regenerated) and stale client caches (the F-6 hard-reload rule). "Preserve prior certified values" is delivered by the close blob + evidence packs at L1, mechanically by the audit log at L2.

| Class | Path | Period effect | Prior value kept? | Owner? | Note/reason required? |
|---|---|---|---|---|---|
| Transaction edit, **uncertified** month | Register edit — current state only, no ceremony | None | L2 only | No — this is Wendy's normal flow; keep it free | No |
| Transaction edit/delete, **certified** month | Prefer offsetting entry over edit; **no hard deletes in certified months** (reversal instead) until L2 exists. Financial-field edits (amount/date/account/category/cleared) flag divergence; cosmetic edits (payee/memo) don't | Divergence flag; reviewed at next close; re-certify only if material | Evidence at L1; L2 later | Not per-edit; owner sees it via divergence review | Yes (one line in close record) |
| Duplicated transaction | Delete while uncertified; reversal after certification. No dedup detector exists today (TX-1-adjacent gap) | As above | — | No | Yes if certified |
| Late-arriving transaction (statement lands after close) | Enter with true `transaction_date` (backdating is legitimate); expected-class divergence; `posted_date`/5F-3 is the eventual proper attribution home. **Never** via `starting_balance` (standing rule) | Divergence, usually absorbed at next close | — | No | Auto-noted via divergence |
| Backdated transaction generally | Allowed; certified months → as above | As above | — | No | If certified |
| Account starting-balance anchor | The **A4 precedent is the procedure**: guarded key-pinned SQL, preflight/postflight in-transaction, evidence, owner-run. Rare by design | Register display only (does not feed model/Budget) | Evidence pack | **Yes** | Yes |
| Weekly balances (`weekly_reconciliations`) | Latest week: 5G-1D `approved_reopen` (owner, DB-enforced, re-stamps `recorded_at`, original kept in evidence). Older weeks: separately reviewed historical-repair plan (Gate-E style). Never plain re-save once 5G-1D activates | Divergence if month certified | Evidence pack only (no DB history) | **Yes** | Yes |
| Category corrections | Recategorization = normal ops uncertified; certified → financial-edit class (moves Budget actuals). Bulk cleanup (TX-1) should run as a one-time reviewed remediation with before/after export — ideally **before** the first certified close of the months it touches | Divergence if certified | Export | Bulk: yes | Bulk: yes |
| Budget-line (BLR) corrections | Edit is from-selected-month-forward by design (interval close + insert — structurally history-preserving; keep). Month-open check: BLR/category sync SQL. Editing certified months' plan lines: discourage; note in close record | Plan is not certified until close, so current-month edits are free | Structural (old interval row survives) | No | If certified |
| Goal registry / target corrections | Precedent: the IRA target correction exposed the waterfall deadlock — registry changes ripple the model. Require: golden-master re-check + snapshot-implication review + owner approval | Model-wide forecast shift; note in next close | Git (registry is seeded/committed) | **Yes** | Yes |
| Snapshot value corrections | **Already governed** (frozen): Option B steady-state (owner-only RPC, existing-row, nearest-existing bounds), Option A guarded-SQL bridge until then; anchor amendments preserve `opening_anchor` + re-approved Value Card; multi-week/backfill only under Gate E. This review adds only: certified-month touch → divergence note | Divergence if certified | External evidence (mandatory, pre-write export F-7) | **Yes** | Yes (note column + pack) |
| Deleted/duplicated reconciliation row | `deleteRecon` must be **restricted for anchored weeks** (posture register #9) and direct table writes revoked (#4–#8) — endorse as pre-close mandatory. Deleting any certified-month week: forbidden | — | — | — | — |
| Commitment repairs (`repair_commitments_for_week`) | Deployed but posture undecided — **Gate C**. It can mutate terminal rows and `balance_basis` for closed weeks and is currently REST-callable by any financial writer. Recommendation into Gate C: **wrap or restrict to owner**, supervised use only, evidence-pack discipline same as snapshots | Divergence if certified | `original_amount_cents` + evidence | **Yes** (recommended) | Yes |

### 5.2 Reopen decision tree

1. Is the error in the **certification itself** (wrong scope, wrong evidence, checklist item falsely passed)? → **Month reopen** (owner, reason code) → correct → re-certify v+1.
2. Is it **week-level data** (balances, commitments, snapshots)? → the 5G-1D weekly paths (reopen latest week / Option B / Gate E). Month diverges; re-certify at next close only if material, else a delta note in the close record.
3. Is it **register/budget data**? → correct per matrix; month diverges; absorbed at next close.
4. **Never reopen to make numbers match.** Corrections carry the change; reopening only changes certification status. (This keeps reopen rare and meaningful — expected frequency well under monthly.)

---

## 6. Exception management

### 6.1 Severity model

- **Blocker** — certification cannot proceed while open.
- **Warning** — certification may proceed with a recorded acceptance (reason, scope, expiry) in the **accepted-variance register**.
- **Info** — visibility only.

Dismissal = acceptance record, never silent. The register formalizes an existing pattern — the $1,100 AMEX holding offset was explicitly designated "KNOWN/expected … do not flag as a reconciliation error until 5G-1B"; that designation, generalized (entry, reason, scope, expiry/review date), is the whole design. Seed entries: the AMEX holding offset (expires at 5G-1B); pre-anchor weeks are recon-only (permanent, by design); excluded goals absent from snapshots (policy).

### 6.2 Exception catalog

| Exception | Detector (status) | Severity | Blocks close? | Primary owner |
|---|---|---|---|---|
| Unreconciled week in scope | Row-existence predicate (exists) | Blocker | Yes | Adam |
| Half-closed week (recon, no snapshots) | 5G-1D branch-G detector (spec'd, frozen) | Blocker | Yes | Adam |
| Snapshots without recon | 5G-1D branch H — corrupt, hard stop (spec'd) | Blocker | Yes — and investigate | Adam |
| Statement tie-out unexplained difference | Manual three-total tie-out (audit-proven method) | Blocker | Yes (per card with statement in M) | Wendy/Adam |
| Missing expected transaction | Statement diff (manual); WD-obligation-without-commitment detector (spec'd in repair detection) | Warning | Disposition required | Wendy |
| Stale balance (no closeout in >7 days at close time) | `recorded_at` age (trivial) | Blocker at close; Warning weekly | Yes | Adam |
| Uncategorized transactions in M | Count query (TX-1 makes it enforceable at entry) | Warning until TX-1; then Blocker | Disposition | Wendy |
| BLR/category desync | validation-blr-category-sync.sql (exists as template) | Blocker at month-open; recheck at close | Yes | Adam |
| Budget line over/near without disposition | UX-0 row states (exist) + close review | Warning | Disposition | Wendy |
| Aged `bank_pending` commitments / Review-Required verdict | Computed (`_reviewRequired`) but **unrendered** — finish the 5F-1 deferral | Warning; Blocker if an in-scope week's verdict never resolved | Disposition | Adam |
| Goal snapshot monotonic anomaly | Normal path hard-stops (spec'd); `correction`-sourced decreases reviewed at close | Warning | Disposition | Adam |
| AMEX attribution invariant (one-sided advisory) | SA8-style check (exists in validation SQL; hard two-sided at 5G-1E) | Warning | Disposition | Adam |
| Nonzero goalVariance at closeout | C3 overlay captures it (exists) | Warning (thresholded) | Disposition | Adam |
| Silent table-load failure (green badge, missing data) | **Gap — must be surfaced** (integrity risk #4) | Blocker for any close-time operation | Yes — you cannot certify what didn't load | Adam |
| Negative cash projection / flight-path breach | Computed today (breach weeks visible) | Info/Warning (projection, not fact) | No | Adam |
| Duplicate close attempt | Unique (period, version) — loud failure by design | Info (logged) | n/a | — |
| Historical edit in certified month | Watermark/blob diff (L1 manual, later mechanical) | Warning | Reviewed at next close | Adam |
| Backup stale or missing pre-close | File+hash check (trivial) | Blocker | Yes | Adam |
| Model-window exhaustion approaching (P4, Cal Wk 53 = Jan 9 2027) | Calendar | Info now; Blocker for the December close if re-baseline unplanned | — | Adam |

### 6.3 Ownership, resolution, escalation

Wendy owns entry-quality exceptions (uncategorized, statement tie-outs she operates, budget dispositions); Adam owns model/correction/certification exceptions and everything owner-gated. Resolution workflow is the close checklist plus the weekly conversation — **no ticketing**. Escalation in a two-person system means one thing: it goes in the close record and, if unresolved, blocks certification.

---

## 7. Operator workflow

### 7.1 Roles (keep as-is)

Wendy: daily Register/Budget entry — **zero new obligations from this design**; her July usability surface just landed and must not grow close ceremony. Adam: weekly Saturday closeout + transfers; all owner-path actions; monthly close. The one-writer-at-a-time household convention plus 5G-1D's locks make concurrency a non-issue.

### 7.2 The operating rhythm

| Cadence | Ritual | Time |
|---|---|---|
| Daily (Wendy) | Enter/clear transactions | unchanged |
| Weekly (Adam, Sat) | Existing closeout (recon + commitments + balances; + snapshot confirm once 5G-1D activates) + **post-closeout backup** + one-glance exception check | +2–3 min over today |
| Monthly (Adam, +Wendy for P3–P6) | Close checklist P1–P9 → evidence pack → certification record | 30–60 min first runs |
| Quarterly | Restore rehearsal on staging; security review (MFA, keys, grants) | ~1 hr |

### 7.3 The eight questions, mapped

- *What needs attention now?* → exception checklist (interim); the surfacing trio (load-failure banner, verdict text, snapshot-gap nag) in-app.
- *What is safe to defer?* → severity model; anything Warning with an acceptance entry.
- *What blocks close?* → the Blocker column, verbatim.
- *What changed since last review?* → watermark diff (interim: `recorded_at`/`updated_at` scan against the last close record).
- *What requires owner approval?* → the fixed list in §2.3 — it should be printed in the checklist header, not re-derived each time.
- *What has already been certified?* → `docs/closes/` — the record series is the register.
- *What failed and how is it retried?* → weekly: 5G-1D branch semantics (idempotent retry, GFA01 adjudication, half-close repair); monthly: re-run the checklist — every step is read-only or idempotent by design.
- *What is the next required action?* → checklist order is the task order.

### 7.4 Dashboard recommendation: defer

A close cockpit fails the materiality test today (two operators, one close a month, checklist suffices). The in-app work that *does* materially improve control is finishing three already-specified surfacing items — the load-failure banner, the Review-Required verdict text, the snapshot-gap nag. A read-only "Close status" card belongs in 5G-6, and any richer "needs attention" surface should be **5F-0** (already planned) rather than a new fork.

---

## 8. Production support and recovery

### 8.1 Failure modes vs capabilities

| Failure | Response today | Gap / action |
|---|---|---|
| Failed RPC (validation error) | Atomic abort, message shown, retry safe (proven design) | None |
| Ambiguous RPC outcome (timeout) | 5G-1D re-read identity protocol before any auto-retry (spec'd) | Extend same doctrine to future write surfaces |
| Partial write across recon+snapshots | Atomic wrapper (frozen); interim half-closes repairable via branch G | None once 5G-1D activates |
| Bad deploy | Revert + push; Pages Builds API fallback (proven in the Actions incident); BUILD_TS visible | Add a standing 5-minute post-deploy smoke list (login, load green, recon panel, Register, Budget) |
| Bad migration | Staging-first, fingerprint guards, rollback scripts, restore point | Best-in-class; keep |
| Accidental user edit | Nothing detects it | Divergence watermark (L1); audit log (L2) |
| Corrupted derived state | Recompute by architecture; F-6 hard-reload rule | None |
| Corrupted observations (recon/snapshot rows) | Correction paths + restore points | Covered post-5G-1D |
| External outage (Supabase/Pages/Actions) | App is unusable without Supabase (accepted for household scale); bank/statement PDFs remain source | Document as accepted; no build |
| Auth failure / owner lockout | **No backup owner account (backlog #9), no MFA (#8)** — and the owner Supabase login is the god path (SQL editor bypasses RLS) | Do both now; ~30 minutes total |
| Stale client state | BUILD_TS + hard-reload doctrine (F-6: an unreloaded session is not evidence) | Optional later: version-mismatch nag |
| Restore from backup | **Unrehearsed.** Free plan (no PITR — the security backlog's "Supabase Pro daily backups" assumption is stale); restore = destructive full replace from local pg_dump; no runbook | Write `docs/restore-runbook.md`; rehearse once on staging **before Quicken cancellation** |
| Replay/regeneration of derived data | Free by design (runModel/Budget recompute) | State the doctrine explicitly: derived = regenerate; observed = restore or correct, never regenerate |

### 8.2 The backup cadence gap (headline)

Backups today are event-driven (before DDL). The last full-data restore point is 2026-07-09 — **before** the E2 anchor seed, the 2.1 holding correction, the Week-5 reconciliation, and all Register entry since. If production data were corrupted today, recovery would be: restore a 3-day-old dump, then re-derive everything since from bank statements and memory. Fix (no code, one script invocation as ritual):

1. **Weekly post-closeout `pg_dump`** (full data, local `~/Herndon-FOS-DB-Backups/`, optional encrypted cloud copy), metadata-only note in `exports/` per the E1 pattern.
2. **Mandatory pre-close and pre-correction dumps** (pre-correction is already mandated for snapshots by F-7 — generalize to all owner-path writes).
3. Simple retention: 8 weekly + 6 monthly.
4. **One restore rehearsal on staging** before Quicken cancellation; quarterly thereafter.

### 8.3 Quicken is a recovery control

During the parallel run, Quicken is an independent, operator-maintained replica of the register — the only one. The cancellation criteria (one clean parallel month of matching totals) measure *accuracy*, not *resilience*. Add a recovery-readiness gate to cancellation: backup cadence live ≥ 4 weeks, restore rehearsed once, statement attestations habitual, September close certified. Otherwise cancellation removes redundancy at the precise moment the OS becomes the sole system of record.

### 8.4 Recovery capabilities required before further major features

(1) Scheduled backups + restore runbook + one rehearsal; (2) backup owner account + MFA; (3) the surfacing trio (you cannot operate what you cannot see fail); (4) posture-register revocations incl. `deleteRecon` restriction (Gate C resolution). All are small; none conflict with the freeze (items 1–2 are not code; 3–4 ride post-freeze slices).

---

## 9. Control framework (proportionate)

| Type | In place (keep) | Add at MVC (≈5G-1F) | Future state (5G-6/5J+) |
|---|---|---|---|
| Preventive | RLS + role model; RPC validation; SECURITY DEFINER write funnels; env fingerprints + hard-stop guards; run-once discipline; UNIQUE natural keys; staging-first; freeze windows; Do Not Touch; test-gated pushes | Posture-register revocations (direct-write revokes; `deleteRecon` restriction; Gate C disposition); month-open BLR sync check; no-delete convention for certified months | FK `budget_line_rules.category_key` → `categories` (wishlist 39, after legacy audit); required category at entry (TX-1); hard AMEX invariant (5G-1E) |
| Detective | Preflight/validation SQL; SA8-class advisories; goalVariance capture; statement tie-out method (audit-proven); Quicken parallel comparison | Exception checklist w/ severity; watermark divergence check; surfacing trio (load failures, verdict, snapshot gaps); accepted-variance register | Audit-log-driven diffs; recurring invariant runner (only when volume justifies automation) |
| Approval | Owner gates (is_owner, DB-enforced); per-action approvals, never inferred; Value Cards; gate registers | Close certification + reopen reason codes; the fixed owner-action list printed in the checklist | DB-enforced certification schema |
| Reconciliation | Weekly recon + commitments state machine; register cleared/statement method; snapshot anchors + completeness predicate | Statement attestations recorded per close; month certification composing all three geometries | Import/OAuth tie-outs (wishlist 26/27) as the eventual missing-transaction detector |
| Audit | Evidence packs + SHA-256 tiers; sentinel/value split; git history; metadata-only commits | Close records series (`docs/closes/`); reason codes; correction-evidence extended to certified-month touches | `financial_audit_log` (L2); event ledger only on demonstrated need (L3) |
| Recovery | Per-phase rollback scripts; event-driven restore points; revert-deploy; identity/inert gates | Scheduled backup cadence; restore runbook + one rehearsal; backup owner + MFA | PITR-class backup (paid plan) if stakes/volume grow; quarterly rehearsal cadence |

**Anti-bureaucracy commitments:** no dual approvals anywhere; no per-edit ceremony in uncertified months; evidence packs only for owner-path writes and closes; accepted-variance register instead of zero-variance theater; checklists before software; file-tier before schema; nothing new for Wendy.

---

## 10. Missing foundational capabilities (before more complexity)

Ranked; 1–6 are foundations, 7–10 are due-when-triggered.

1. **Scheduled backup cadence + restore runbook + rehearsal** — the recovery floor (§8.2).
2. **Backup owner account + Supabase MFA** — continuity of the god path (backlog #8/#9, both open).
3. **Run-time visibility floor** — load-failure banner, Review-Required verdict rendering, snapshot-gap nag. All three are already specified in prior phases; this is finishing, not designing.
4. **Close certification record + basis watermark** (file-tier) — creates the certified-vs-current distinction everything in §3–§5 relies on.
5. **Statement attestation habit** (rows in the close record) — makes card reconciliation durable instead of a live panel.
6. **Weekly-recon accountability** — Gate C disposition + Slice-7 revocations + `deleteRecon` restriction; add attribution columns or fold into L2.
7. **`financial_audit_log`** (L2) — trigger: third owner correction in a quarter or Quicken cancellation.
8. **TX-1** (required category, uncategorized review, reimbursement/offset taxonomy) — category-level certification is soft until this lands; also the only home identified for the Jabian reimbursement-status gap (open since 5E-10).
9. **2027 re-baseline design** (P4) — model-window exhaustion Jan 9 2027; `weekly_reconciliations` has no `model_year`; plan by Nov 2026 or the December close inherits it as a Blocker.
10. **Dual-actuals retirement decision** — `budget_transactions` legacy rows vs `transactions` (additive summing works; a certified system should eventually have one actuals store).

**Explicit non-needs now:** event-sourcing ledger; close cockpit UI; stored workflow-state tables; alerting infrastructure; plan upgrade for PITR; any new Wendy-facing surface.

---

## 11. Prioritized recommendations

### 11.1 Recommended month-end operating model (summary)

Weekly fully-closed weeks (5G-1D) remain the atomic unit. Month-end close = derived readiness over P1–P9 → owner certification with basis watermark + evidence pack (E2 pattern, file-based first) → divergence detection thereafter. Statement cycles reconcile per card into the close record; budget month review is a certification input, not a lock. Reopen is owner-only, reason-coded, append-only, rare. **Confidence: high.**

### 11.2 Recommended close/reopen state machine (summary)

Three persisted facts (certifications, reopens, nothing else), derived OPEN/CERTIFIED/REOPENED/DIVERGED, transitions per §3.2, month-N+1 requires month-N certified, duplicate certification fails loudly, weekly-machine interlock via divergence flagging. **Confidence: high.**

### 11.3 Minimum viable control set (before/at first formal close)

| # | Control | Cost | Confidence |
|---|---|---|---|
| M1 | Weekly + pre-close/pre-correction backups; restore runbook drafted | Ritual + 1 doc | High |
| M2 | Backup owner account + MFA on Supabase | ~30 min, owner | High |
| M3 | Close checklist v1 (P1–P9) + July close executed file-based + certification record in `docs/closes/` | 1 doc + one afternoon | High |
| M4 | Accepted-variance register seeded (AMEX holding offset, pre-anchor weeks, excluded goals) | 1 doc | High |
| M5 | Exception catalog adopted; Blockers enforced manually via checklist | In M3 | High |
| M6 | Owner-action list + reopen rules adopted (reason codes) | In M3 | High |
| M7 | Statement tie-out attestation per card statement in scope | Ritual | Medium-high (cycle-boundary mechanics may need one iteration) |
| M8 | 5G-1D completes as frozen, incl. Option B + Gate C resolved + Slice-7 revocations + `deleteRecon` restriction | Already in flight; Gate C is the one open decision this review feeds | High |
| M9 | Surfacing trio finished (load-failure banner, verdict text, snapshot nag) | Small app slices, post-freeze | High |

### 11.4 Future-state control set

`financial_audit_log` + weekly-recon attribution (5J / L2); close schema + mechanical divergence (5G-6); hard AMEX invariant + holding lifecycle (5G-1B → 5G-1E); TX-1; import/OAuth tie-outs (wishlist 26/27); 2027 period model incl. `model_year`; quarterly restore rehearsals; read-only close card (5G-6) / needs-attention surface (5F-0). **Confidence: medium** on timing, high on content.

### 11.5 Major risks in the current direction

1. **Recovery posture** — event-driven backups, unrehearsed destructive restore, no PITR, single owner identity, Quicken cancellation removing the last replica. *Severity: highest; cost to fix: lowest.*
2. **Mutable, unattributed, deletable close basis** until Gate C/Slice-7 land — a certified month's foundation can silently change or vanish today.
3. **In-place corrections with external-only history** — fine at current volume, degrades with each correction; watch the L2 pull-forward triggers.
4. **Run-time invisibility** — closes certify what the operator saw; silent load failures and unrendered verdicts mean the operator may not see everything.
5. **Period-geometry conflation** — weeks/months/cycles plus dual week-numbering plus roadmap-numbering drift; certifications must pin scope explicitly or "July is closed" will mean four different things.
6. **Single-operator concentration** — every owner path, correction, and recovery runs through Adam; Wendy cannot correct or recover. Mitigation is runbooks + the backup owner, not role changes.
7. **2027 re-baseline** (P4) — unplanned, collides with the December close.

### 11.6 Sequencing and dependencies

| Window | Work | Depends on |
|---|---|---|
| Now → Jul 23 (pre-freeze) | M1, M2, M4 drafts; M3 checklist authored; 5G-1D execution continues (frozen); Gate C decision made within 5G-1D | Adam time only; no code, no freeze conflict |
| Jul 24 – Aug 10 (Alaska freeze) | Nothing merges; weekly closeouts continue as feasible; weeks will accumulate as half-closes if 5G-1D activation is post-freeze (expected, per Gate D default) | — |
| Aug 11–17 | 5G-1D post-freeze activation + sequential half-close gap repair (≈ weeks 6–9) → **July close executed (first formal close, file-based)** | 5G-1D activation; M1–M6 |
| Late Aug – Sep | M7 statement attestations each cycle; M9 surfacing trio ships; August close (~Sep 5); 5G-2 (planned outflows) proceeds independently | M9 is small app slices; 5G-2 has its own gates |
| Early Oct | **September close = Quicken-cancellation instrument**: certified + recovery-readiness gate (backup cadence ≥4 wks, restore rehearsed, attestations habitual) | M1 rehearsal done |
| Oct – Nov | L2 decision point (audit log at 5J or pull-forward); close schema design (5G-6) if ritual stable; 2027 re-baseline plan (P4) | Correction-volume trigger; Quicken retired |

Dependencies on planned phases: 5G-1D (frozen) delivers the weekly machine, Option B, and the posture register this model assumes; 5G-1B → 5G-1E deliver the holding lifecycle → hard invariant upgrade path; 5F-0 is the eventual needs-attention home; 5G-3 (allocation view) benefits from, but does not hard-require, a certified close — however **legacy-5G-3 (Budget identity change, "high risk" per the stabilization spec) should not land before the audit log (L2) exists**, because it is exactly the class of change whose before/after must be reconstructable.

### 11.7 Mandatory vs. can-wait

**Mandatory before the first formal close:** M1–M8 (M8 = 5G-1D completing its own frozen scope; M9 strongly recommended but a checklist can compensate for one close).
**Can safely wait:** close schema/UI; audit log (until a trigger fires); TX-1 (accept category Warnings in early closes); statement attestation *schema* (file rows suffice); event ledger; 5F-0; any Wendy-facing change; PITR-class backups.

### 11.8 Confidence summary

High: weekly-spine composition; certify-don't-lock; 3-state machine; backup/recovery set; file-based first close; divergence-over-reopen doctrine; Gate C restriction recommendation. Medium: statement-cycle mechanics (first iteration will teach); L2 pull-forward triggers; exact exception severities (expect one recalibration after the July close); sequencing dates (freeze/trip variance). Low/speculative: everything in §11.4 beyond 5J scope — deliberately so.

---

## 12. Challenged assumptions (register)

1. *"Month-end close is the primary control moment."* → **Partly rejected.** The week is the control moment; the month is a certification and review overlay. Building month machinery first would duplicate the spine.
2. *"The period lifecycle needs 8 states."* → **Rejected.** 3 persisted facts + derived predicates, per the system's own 5G-1D doctrine.
3. *"Certified records must be immutable, so financial data should be locked after close."* → **Rejected.** Certifications are immutable; data stays correctable with divergence detection. Locks fight statement lag, backdating, and the posted_date design.
4. *"Corrections need heavier ceremony."* → **Rejected for uncertified months** (Wendy's flow stays free), **confirmed for certified scope and owner paths** — where 5G-1D's evidence discipline already sets the right bar; extend it, don't add a second bureaucracy.
5. *"Auditability requires an event ledger."* → **Deferred.** Watermark + evidence packs now; one generic audit-log table at 5J; ledger only on demonstrated need.
6. *"The system's audit posture is weak."* → **Refined.** Change-time audit is exceptional; run-time audit is thin and uneven (commitments strong, recon/register weak). Fix the asymmetry, not "audit" in general.
7. *"Backups exist because the project takes restore points."* → **Rejected.** Restore points are migration artifacts, not a cadence; the security backlog's Pro-plan assumption is stale; recovery is the single weakest area relative to its cost to fix.
8. *"Quicken parallel run is only an accuracy test."* → **Rejected.** It is also the only independent replica; cancellation criteria must include recovery readiness.
9. *"A close dashboard would improve control."* → **Mostly rejected for now.** Three already-specified surfacing items + a checklist deliver ~90% of the control value at ~10% of the cost; a cockpit is 5G-6/5F-0 territory.

---

*End of review. Advisory input only; no phase scope, gate, or Do Not Touch item is modified by this document.*
