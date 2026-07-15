# Monthly Close v1 — Specification (file-based; reframed 5G-1F)

**Date:** 2026-07-14
**Type:** Implementation-ready specification. **Docs only. No implementation authority.** No code, SQL, schema, migration, RLS, RPC, test, `BUILD_TS`, or production/staging change is authorized or implied by this file.
**Standing:** `AGENTS.md`, `CODEX_STATUS.md`, cleared 5G-1D scope, the Do-Not-Touch list, and Wendy-confirmed workflow win on any conflict. Committed content is **balance-free** — dollar amounts and statement figures live only in local execution copies / off-device evidence, never here.
**Authority:** `docs/roadmap/canonical-roadmap.md` §3 (P3) / §9 (taxonomy). This is the "operating-model control review is its spec" phase — it needs **no Fable review**; if the spec is challenged, the freeze substitute chain (§11.2: ChatGPT adversarial review + conformance against the approved Fable architecture + Adam approval) applies.
**Companion:** `docs/monthly-close-v1-operator-runbook-2026-07-14.md` (the step-by-step operator checklist).

---

## 1. Purpose

**Objective.** Establish a repeatable, file-based **monthly certification** that asserts: every weekly closeout in the month is fully closed, contiguous, and internally consistent; the month-end account/holding balances reconcile to the real bank/credit-card **statements**; and the certified state is recorded with a **basis watermark** so any later change to a closed period is detectable as **divergence**.

**Business purpose.** With Quicken retired, the Financial OS is the **sole live system of record**. There is no external replica to cross-check against. Monthly Close v1 is the **primary period-integrity control**: the certify-and-detect-divergence ritual (plus statement attestation) *is* the trust layer that a bookkeeping tool's reconcile screen used to provide. It also produces the artifact a CPA or a future audit tier can consume.

**Why Monthly Close v1 is intentionally file-based.**
- **Reversibility & speed to value (Decision principle 6, §2 of the roadmap):** a checklist + a committed markdown certification record + a 3-fact state model delivers the control *now*, with zero schema risk, and can run the moment 5G-1D activates.
- **Freeze-safe:** it is zero-code, so it can be specified during the freeze and executed post-freeze without any `main` merge or cash-model change.
- **It builds the primitive the audit model composes over:** certification, basis watermark, divergence detection, and a reason-code vocabulary are the foundation that L2/L3, the Budget-Identity Change, and the schema-tier close (5G-6) later build on. A schema-tier close is deliberately deferred until **≥ 3 stable file-based closes** prove the model (§8).
- **Adding *any* code would forfeit its freeze-adjacent slot** and its zero-risk posture (Fable SR-5).

**Relationship to weekly reconciliation.** Weekly reconciliation (5F-1 + the 5G-1D atomic closeout wrapper) is the **source of truth** the monthly close certifies over. The monthly close **writes no financial data** and **re-runs no engine** — it reads the already-persisted weekly closeouts (`weekly_reconciliations` rows + their nine `goal_funding_snapshots`) and the account balances, verifies them against statements, and records a certification. Weekly = produce the closed weeks; Monthly = certify the set and detect later drift. The monthly close depends on the **fully-closed weekly predicate** (`closeoutState(n)==='complete'`), which exists only after 5G-1D activation.

---

## 2. Scope

**In scope (v1):** the **July 2026 monthly close** as the first instance, then a monthly cadence (August ~early Sep, etc.). Each close:
- certifies the set of weekly closeouts whose week falls in the month;
- attests month-end account/holding balances against statements;
- records a committed, balance-free certification record and a basis watermark;
- derives period state from certification + reopen records (§3.4).

**First realistic execution window: Aug 11–17.** July cannot close until the last July-bearing week is durably closed. Under the Alaska skip posture (§6/§7 of the roadmap), weeks 8 and 9 are **skipped during the freeze** and **caught up Aug 11–15**. July's month-end depends on **model wk 8 (Cal Wk 30, the Aug-1 closeout, which captures the week containing Jul 31)** being fully closed → the earliest honest July close is **after wk 8 durably closes**, i.e. **Aug 11–17**.

**Prerequisite contiguous closeouts.** The July close requires the July weekly closeouts to be **present, fully closed, and contiguous** — expected set **model wk 6 (Cal Wk 28, Jul 18), wk 7 (Cal Wk 29, Jul 25), wk 8 (Cal Wk 30, Aug 1)**. (The operator enumerates the actual month-bearing weeks at close time; wk 5 is the E2 **opening anchor**, not a closeout, and is out of the file-based close's certification scope.) A gap or a half-closed week is a **hard failure** (§4.11) — the close does not certify a discontinuous month.

**Gate C dependency.** The close must assert the **post-Phase-2 grant posture** (F-09), not a bare "activation." Certification is invalid unless, at close time: wrapper (`save_weekly_closeout_with_snapshots`) + Option B (`correct_goal_funding_snapshot`) = owner path only; **old recon RPC / repair RPC / direct snapshot RPC = revoked; snapshot table INS/UPD(/DEL) = revoked.** If 5G-1D activated but Phase-2 lockdown has not completed (a §7 contingency stop state), the month is closed **only under a recorded accepted variance** citing the missing lockdown, expiring when Phase-2 completes.

**Certification boundary (what a close certifies — and does NOT).**
- **Certifies:** the month's weekly closeouts are complete, contiguous, consistent (9 snapshots each; monotonic guards intact), the grant posture is correct, and month-end balances reconcile to statements (or carry a named accepted variance).
- **Does NOT certify / is NOT:** a re-run or re-derivation of the model; a change to any weekly row; a Budget-identity assertion; a tax filing; a guarantee about weeks outside the month; anything about pre-activation legacy weeks.

---

## 3. Definitions

**3.1 Close basis.** The immutable set of inputs a close certifies over: (a) the enumerated month-bearing `weekly_reconciliations` rows and their nine `goal_funding_snapshots` each; (b) the month-end account/holding balances as read from the Register/accounts; (c) the corresponding bank/credit-card **statements** for the month. The basis is *recorded* (weeks + as-of date), never *copied with values* into the committed record.

**3.2 Basis watermark.** A recorded high-water mark captured at certification: the **maximum server-owned write timestamp** (`recorded_at` / `updated_at`) across the certified weeks' rows, plus the **certification timestamp** itself. Purpose: any subsequent write to a certified week with a timestamp **after the certification timestamp** is a **divergence** signal (§4.9). *Note (F-03):* trip catch-up rows carry an August `recorded_at` on July `week_num`s — legitimate and benign; the watermark keys on *new writes after certification*, not on the calendar month of `recorded_at`. The first July close records this nuance explicitly.

**3.3 Statement attestation.** The operator reconciles the OS's month-end account/holding balances against the actual bank/credit-card statements and attests **matched** (or records a named **accepted variance**, e.g. the AMEX holding offset that 5G-1B later expires). The committed record states *matched / variance-noted*, never the dollar figures.

**3.4 Certification record & the 3-fact state model.** The close persists **two kinds of fact** (as committed files, not schema): **certification records** and **reopen records**. Period state is **derived**, never stored as a mutable status:
- **OPEN** — no certification record for the period.
- **CERTIFIED** — a certification record exists and no later reopen/divergence.
- **REOPENED** — a reopen record exists after the last certification (§4.10).
- **DIVERGED** — a write to a certified week postdates the certification watermark with no reopen record (§4.9) — an *unexpected* change requiring investigation.

The canonical certification record for July is `docs/closes/2026-07-close.md` (balance-free).

---

## 4. Monthly close process

**4.1 Close basis capture.** Enumerate the month-bearing weeks; record the week set and the as-of month-end date. Confirm each week's `closeoutState(n)==='complete'`.

**4.2 Watermark capture.** Record the max server write timestamp across the certified weeks and the certification timestamp (§3.2).

**4.3 Statement attestation.** Reconcile month-end account/holding balances to statements; attest matched or record a named accepted variance (§3.3). Values stay in the local worksheet; the record states the outcome.

**4.4 Certification record authoring.** Author `docs/closes/<YYYY-MM>-close.md`: period, week set, as-of date, watermark, grant-posture assertion (§2 Gate C), attestation outcome, evidence pointers, accepted variances, operator sign-off. **Balance-free.**

**4.5 Completeness verification.** Assert: every month-bearing week present and contiguous (no gap); each `complete` (no `half_closed`/`corrupt`); each carries exactly **nine** snapshots; monotonic/non-decrease guards intact; the Week-5 opening anchor unchanged (nine `opening_anchor` + the two `correction` rows).

**4.6 Reconciliation inputs.** The weekly closeouts (server-derived eligible nine, `source='reconciliation'`), the account/holding balances, and the statements. No manual recomputation of model outputs — the close reads, it does not derive.

**4.7 Evidence package.** Local (off-device, balance-free-committed): statement-reconciliation worksheet; a pre-close `pg_dump` (DR-1 cadence, §5.3); screenshots/exports of the weekly `complete` badges and the grant-posture query result; the committed certification record. Evidence *pointers* (not values) go in the record.

**4.8 Table verification (read-only assertions).** Confirm, by read-only query/UI: the certified weeks' `weekly_reconciliations` rows exist and are complete; nine snapshots per certified week; the grant matrix matches the post-Phase-2 target (F-09); no unexpected rows in the certified weeks since the prior close. *(Read-only — the close performs no writes.)*

**4.9 Divergence handling.** If a certified week shows a write with timestamp **after** its certification watermark and **no** reopen record exists → the period is **DIVERGED**. Action: investigate root cause (unexpected mutation of a closed period is a control incident), record a **divergence note** in the certification record, and either (a) reconcile + **re-certify** (§4.11) if the change is legitimate and now correct, or (b) escalate to the correction/reopen procedure if remediation is needed. A DIVERGED period is never left silently.

**4.10 Reopen handling.** A legitimate need to change a certified week (e.g. an owner-approved Option B correction) is recorded as a **reopen record** *before* the change → period becomes **REOPENED**. The reopen record names the week, reason, approver, and links the correction evidence. Reopening a certified month is an owner-only, explicitly-recorded act — never an ambient edit.

**4.11 Re-certification.** After a REOPENED/DIVERGED period's weeks are corrected and re-verified (§4.5), author a **new certification record** (append; never edit the prior one) with a fresh watermark. The period returns to **CERTIFIED**. History is append-only: prior certification and reopen records are retained (they are the audit trail).

**4.12 Operator checklist.** Execution is driven by the companion `docs/monthly-close-v1-operator-runbook-2026-07-14.md` — each step has a verbatim expected result and a pass/fail gate.

**4.13 Failure conditions (any → do NOT certify).** Missing or non-contiguous month-bearing week; a `half_closed`/`corrupt` week; snapshot count ≠ 9 on a certified week; monotonicity/non-decrease break; grant posture wrong (old RPC still granted, or table INS/UPD not revoked) without a recorded accepted variance; statement mismatch beyond a named accepted variance; the Week-5 anchor altered. On any failure: stop, record the condition, remediate through the proper (weekly/correction) path, then re-run the close.

**4.14 Exclusions (explicit).** No schema, no new tables (v1 is file-based); no automated divergence job (manual/checklist detection in v1); no dollar amounts or statement figures in committed files; no Budget-identity change; no cash-model / `runModel` change; no reopen or correction *performed by* the close (the close *records* them, the weekly/Option-B path performs them); no certification of pre-activation legacy weeks; no CPA export format lock-in (v1 record is the CPA-consumable artifact as-is).

**4.15 Acceptance criteria (the July close is done when).** `docs/closes/2026-07-close.md` is committed and balance-free; all July-bearing weeks are present, contiguous, `complete`, nine-snapshot, monotone; the post-Phase-2 grant posture is asserted (or an accepted variance is recorded); statements are attested matched-or-variance-noted; the basis watermark is recorded (with the late-`recorded_at` note); evidence pointers are present; Adam has signed the certification; the derived state is **CERTIFIED**; a line is appended to `docs/decision-log.md` (certification is a governance event).

---

## 5. Operational controls

**5.1 Evidence retention.** The committed certification record is retained in-repo (append-only across months). Balance-bearing supporting evidence (statement worksheets, dumps) is retained **off-device, encrypted**, per the DR-1 cadence — never committed.

**5.2 Recovery considerations.** The certification record + watermark make the close a **DR checkpoint**: after a restore, the operator can verify no post-close divergence by comparing current certified-week timestamps against the recorded watermark. A close is not valid without a corresponding **pre-close dump** (§5.3).

**5.3 Interaction with DR-1.** The DR-1 dump cadence includes **pre-close** dumps (§5 item 1 of the roadmap). A monthly close is a natural DR moment: take/verify the pre-close dump, then certify. DR-1 must be **closed** before the first post-5G-1D implementation work, but Monthly Close v1 is **zero-code** and its first run is a control operation, not implementation — it proceeds once activation + the July weeks + DR-1 evidence exist.

**5.4 Interaction with the Alaska operating posture.** No monthly close runs mid-trip (closes are a desktop, statement-in-hand operation; the trip rule is "read-only, write it down, don't touch it"). July closes **after return**, once wk 8 catch-up completes (Aug 11–15) — first July close Aug 11–17.

**5.5 Interaction with skipped weekly closeouts.** A skipped week is not closeable-over until it is **caught up** (closed sequentially through the wrapper). July's close waits on the wk-8 catch-up; August's close waits on wk 9/10 catch-up. A month with an un-caught-up skipped week **cannot certify** (§4.13 non-contiguity).

**5.6 Interaction with Week-28 activation.** The `complete` predicate exists only **post-activation**; model **wk 6 = Cal Wk 28** is the **first** supervised closeout. The July close therefore certifies the *first* real weekly closeouts. If activation slipped post-freeze (§7 contingency), the July close slides with it (≈ Aug 18–24) but the spec is unchanged — it always certifies the month's actual, post-activation weekly closeouts.

---

## 6. Testing

**6.1 Operator validation.** The operator (Adam) runs the companion runbook; every assertion has a verbatim expected result and a pass/fail gate. A close is validated by the runbook passing end-to-end, not by any automated suite (v1 has none).

**6.2 Review process.** Monthly Close v1 needs **no Fable review** — the operating-model control review *is* its spec. If the spec is challenged during the freeze, the **substitute chain** applies (§11.2 of the roadmap): **ChatGPT adversarial review + conformance against the approved Fable architecture + Adam approval.** The *first* certification record is reviewed by Adam before sign-off (§6.4).

**6.3 Dry-run expectations.** Before the real July close, run the runbook as a **dry run** over the already-closed weeks (wk 6/7) to validate the checklist mechanics, the grant-posture query, and the watermark capture — with **no certification record committed** (dry runs certify nothing). A dry run surfaces checklist defects cheaply.

**6.4 Certification review.** The committed certification record is reviewed by Adam (completeness, grant-posture assertion, attestation outcome, watermark, evidence pointers, balance-free) **before** sign-off flips the derived state to CERTIFIED.

**6.5 Future automation boundaries.** v1 is **manual/file-based by design**. Do **not** build in v1: a schema `closes`/`certifications` table; an automated DIVERGED-detection job; a close cockpit UI; email/alerting. Automation is deferred to **5G-6 Close hardening (schema-tier)**, gated on **≥ 3 stable file-based closes** (possibly never — and that is acceptable, Fable SR-5). Any automation must preserve the v1 semantics (certification + reopen facts → derived state; append-only; balance-free commits).

---

## 7. Commit strategy (future implementation sequence — no code now)

v1 "implementation" is authoring + committing documents; there is no application code. Sequence:
1. **Freeze (Jul 29 – Aug 10):** finalize this spec + the operator runbook + a `docs/closes/<month>-close.md` **template** (balance-free). Branch-held; no merge.
2. **Aug 11–15:** wk 8 → wk 9 catch-up closeouts (weekly path); wk 10 normal Sat Aug 15.
3. **Aug 11–17:** **dry-run** the runbook over wk 6/7 (§6.3); then run the **real July close** over the July-bearing weeks; author `docs/closes/2026-07-close.md`; Adam reviews (§6.4) and signs.
4. **Commit** the certification record and the templates — **docs-only**, using `git commit --no-verify` to keep `index.html`/`BUILD_TS` untouched (the pre-commit hook stamps `BUILD_TS` otherwise). No push beyond the normal post-freeze flow; no `main` cash-model merge.
5. **Append** a line to `docs/decision-log.md` (certification = governance event). **Do not** append to `docs/execution-ledger.md` — no SQL ran against production.
6. **~Sep:** August close (2nd iteration, over cleaner data), same runbook.
7. **After ≥ 3 stable closes:** evaluate **5G-6** schema-tier hardening (separate spec, separate gates). Until then, stay file-based.

---

## 8. Repository-correctness notes carried by this spec

- **Repository freeze is `Jul 29 – Aug 10, 2026`** (not Jul 24). Gate D's "before Jul 24" is the activation *target*; Jul 25–28 is contingency margin.
- **Fable independent-review access ends `Jul 19, 2026`.** Nothing in the close's review path depends on Fable.
- **During the freeze, Fable review is replaced by:** ChatGPT adversarial review → conformance against the approved Fable architecture → Adam approval (canonical roadmap §11.2). Monthly Close v1 is zero-code, so this substitute chain applies only if the *spec itself* is challenged.

---

*Specification only. No implementation, code, SQL, schema, migration, RLS, RPC, test, `BUILD_TS`, or production/staging change. Adopt/execute per Adam approval and the canonical roadmap sequence.*
