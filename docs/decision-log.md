# Decision Log

**Role:** Governance tier of the History layer (four-document model). **Append-only.** One line per **made** decision (the registers in the living roadmap §12 track only *open* decisions). Completes the audit ladder: L2 = row mutations, L3 = domain events, **decision log = governance events**.
**Authority:** `docs/roadmap/canonical-roadmap.md` §14 (AF-9). Seeded from the A-list as it resolves. **Secrets-free, balance-free.**

| Date | Decision | Approver | Evidence |
|---|---|---|---|
| 2026-07-13 | Gate D — Option A (pre-freeze activation) | Adam | `CODEX_STATUS.md` "## 5G-1D BROWSER COMPLETE + GATE D DECIDED" |
| 2026-07-13 | Gate C — all 11 write-surface dispositions approved (approved, not executed) | Adam | `docs/phase-5g-1d-gatec-register-2026-07-13.md` |
| 2026-07-14 | A1 — Adopt the FINAL roadmap as amended (→ APPROVED — controlling); produce the single living canonical roadmap | Adam | `docs/roadmap/canonical-roadmap.md` §0 |
| 2026-07-14 | A2 — Freeze dates confirmed `Jul 29 – Aug 10` (controlled repository-stability period) | Adam | canonical-roadmap §0 / §11.3 |
| 2026-07-14 | A4 — Alaska posture: deliberate skip + sequential catch-up (wk 8, wk 9) | Adam | canonical-roadmap §6 |
| 2026-07-14 | A5 — Adopt the activation contingency annex | Adam | canonical-roadmap §7 |
| 2026-07-14 | A13 — Wishlist-34 December trip routes to 5G-2 `planned_outflows` | Adam | canonical-roadmap §3 P5 / Appendix B |
| 2026-07-14 | A14 — 1B reviewer chain in Fable's absence = ChatGPT challenge + §4 conformance + Adam | Adam | canonical-roadmap §11.2 |
| 2026-07-14 | A15 — Split Register bundle P3b-1/P3b-2; fold 5G-1E into 1B as demotable 1B-S4 | Adam | canonical-roadmap §13 SR-1/SR-2 |
| 2026-07-14 | A17 — Elevate the Edge Function layer to first post-rollover platform enabler (early 2027) | Adam | canonical-roadmap §13 SR-4 |
| 2026-07-14 | A18 — DOC-1: one living canonical roadmap now; DOC-2/DOC-3 later | Adam | canonical-roadmap §16 |
| 2026-07-14 | A16 — D10 option (c) authorized for the November menu; **decision deferred** (not selected now) | Adam | canonical-roadmap §12/§13 SR-3 |
| 2026-07-14 | A19 — Verify Supabase inactivity-pause policy before departure; document unpause; verification pending | Adam | canonical-roadmap §14 AF-3 |
| 2026-07-14 | Wishlist reconciliation approved (live production export mapped; Fable ID/status corrections applied) | Adam | canonical-roadmap Appendix B |
| 2026-07-14 | Roadmap UI Lite recorded as a new future candidate (W-8); Wishlist items 32/33 subsumed | Adam | canonical-roadmap §17 |
| 2026-07-14 | Monthly Close v1 spec + operator runbook drafted (spec/runbook only; no implementation) | Adam (directed) | docs/monthly-close-v1-spec-2026-07-14.md; -operator-runbook-2026-07-14.md |
| 2026-07-14 | T-1 — TX-SPLIT default Jan 2027 (first post-rollover) / 5G-2 November; conditional Nov swap (4 preconditions, decide ≤ Oct 1) | Adam | canonical-roadmap §3.0 / §12.3; Fable Targeted Sequencing Review + Amendment 1 |
| 2026-07-14 | T-2 — Fold BUD-MX-lite into P3b-1 as P3b-1.MX (Misc/Extra Envelope v1); resolves W-3; identity 20% stays Budget-Identity Change | Adam | canonical-roadmap §3 P3b-1; Amendment 1 §3 |
| 2026-07-14 | T-3 — Dissolve "Stage 1A"; no separate Architecture Enablement code phase; pre-1B prep bright line (§8) | Adam | canonical-roadmap §8 / §9 / §3.0; Amendment 1 §2 |
| 2026-07-14 | T-4 — 5G-5 renamed "Goal Intelligence & Timeline" + GT-R read-only trajectory carve-out (interleave-class) | Adam | canonical-roadmap §3 P6 / §12.3 |
| 2026-07-14 | T-5 — Re-date 5G-4a/4b/full 5G-5 to 2027 (honesty change; no scope change) | Adam | canonical-roadmap §3.0 / §3 P6 |
| 2026-07-14 | T-6 — Adopt Account Composition Visibility Rider (AMEX Savings + Truist Savings; Checking deferred to 5G-3; not `5G-3A`) | Adam | canonical-roadmap §18; Fable Amendment 2 |
| 2026-07-14 | Provenance: three Fable 2026-07-14 sequencing documents adopted as controlling amendments (targeted review + boundary clarifications + account composition scope) | Adam | docs/roadmap/archive-index.md |
| 2026-07-14 | 5G-1B RG-1 review received (ADOPT WITH CHANGES); C-1…C-5 folded into the architecture package; B-11/B-12 added, B-10 amended | Fable (review) | docs/phase-5g-1b-architecture-2026-07-14.md; Fable 5G-1B Architecture Review - 2026-07-14.md |
| 2026-07-14 | 5G-1B final contract corrections: `effective_at timestamptz` (not date; closed-week via governing tz); `correction` event type removed → four financial types, corrections = reversal + replacement | Adam | docs/phase-5g-1b-architecture-2026-07-14.md §4/§8/§9 |
| 2026-07-14 | 5G-1B decisions B-6, B-7, B-8, B-10, B-11, B-12 APPROVED (model-freeze exception limited to the seam + golden-master-verified; 1B-S4 + demote valve; golden recapture only with expected-effect record + Adam review; authenticated owner REST normal path / SQL-editor read-only / service-role break-glass; note-required basis_adjustment no override; effective_at timestamptz + created_at) | Adam | docs/phase-5g-1b-architecture-2026-07-14.md §19 |
| 2026-07-15 | Open-window executed-transfer netting/suppression control adopted as a **mandatory 5G-1D Gate B activation blocker**; adapter/projection + write-guard only, no frozen-surface change; Saturday slips if it cannot meet the bar (no fallback to the old package) | Adam | docs/phase-5g-1b-openwindow-netting-2026-07-15.md §D |
| 2026-07-15 | Netting classes `target_accumulation` (the nine) + `fixed_once` (`goal_adam_ira_seed`, no cross-net); dispositions normal/partial/suppressed/blocked; six fail-closed conditions; render-disable **and** write-path revalidation | Adam | docs/phase-5g-1b-openwindow-netting-2026-07-15.md §B/§D |
| 2026-07-15 | Inline-adjacent implementation this week; **no ES-module extraction** — standing exception recorded, modularization roadmap preserved | Adam | docs/phase-5g-1b-openwindow-netting-2026-07-15.md §D.7 |
| 2026-07-15 | Progress-plane transfer-identity gap recorded; `holding_events` (RCCL/DCL) cannot serve as the progress-plane durable identity; layers a/b/c/d separated with owning phases | Adam | docs/roadmap/amendment-2026-07-15-progress-plane-transfer-identity.md |
| 2026-07-15 | Saturday operator package reissued (repin HEAD/BUILD_TS/static+e2e+readiness counts; add production precheck, pre-close duplicate scan, Week-6 cumulative-includes-executed-residual, post-close zero-later-recommendation). **Activation itself remains unauthorized pending independent review + Adam go-ahead.** | Adam (directed) | docs/phase-5g-1d-saturday-operator-package-2026-07-18.md |

*Append-only. Seed further rows as A3/A6/A7–A12 and future decisions resolve (e.g., DR-1 sign-off, A6 patch approval, D7/D6/D10/D-11).*

---

*Append-only. Secrets-free, balance-free.*
