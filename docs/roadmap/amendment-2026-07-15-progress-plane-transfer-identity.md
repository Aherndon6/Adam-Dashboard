# Roadmap / Decision Amendment — Progress-Plane Transfer-Identity Gap

**Date:** 2026-07-15 · **Status:** recorded (governance) · **Authority:** `docs/roadmap/canonical-roadmap.md` (append; the roadmap's git history is its changelog). **Balance-free.**
**Trigger:** the open-window executed-transfer duplicate (Adam IRA $61.06) — see `docs/phase-5g-1b-openwindow-netting-2026-07-15.md`.

## Finding

The reported defect exposed that the **progress plane** (the nine snapshot-eligible goal-funding obligations: `adam_ira`, `wendy_ira`, `wendy_sep`, `alaska`, `bailey_529`, `bryce_529`, `preston_529`, `bryce_vehicle`, `christmas_cruise`) has **no durable per-execution transfer identity**. Executed transfers persist positionally in `weekly_tasks` (`action_key` + `completed_amount`), which is sufficient for the `resolveWeekTransfers` history adapter and the new netting control, but is **not** a durable, immutable obligation/execution identity.

The **5G-1B `holding_events` ledger deliberately scopes to the excluded holdings `wewe_rccl` / `wewe_dcl` and rejects the eligible nine** (`docs/phase-5g-1b-architecture-2026-07-14.md` §4/§7, C-4). Therefore `holding_events` **cannot currently serve** as the promised durable identity solution for the class of defect just observed on the progress plane. This amendment records that boundary so a future phase closes it deliberately rather than by assumption.

## Four distinct layers (do not conflate)

| # | Layer | What it is | Status / owning phase |
|---|---|---|---|
| a | **Adapter-level netting control** (this correction) | Pure projection that suppresses/nets/blocks already-satisfied open-window goal transfers; write-guard revalidation. Adapter + write-guard only; no schema. | **DONE (5G-1B rider, 2026-07-15).** Complements 5G-1D snapshots; not a durable-identity substitute. |
| b | **Structured obligation / execution identity for the progress plane** | A durable, immutable identity for each model-generated goal transfer + its executions (replaces positional `weekly_tasks` keying as the effective identity), with proven uniqueness semantics across multi-action goal families. | **OPEN — assign to a post-1B progress-plane identity slice (candidate: `1B-S5` / fold into the L3 ledger work, §8/P8).** Prerequisite before any additive `weekly_tasks` schema/write-path migration. |
| c | **Model-year rollover support** | The netting cycle is bounded by `model_year`; obligation identity and netting must remain correct across the 2026→2027 rollover (no cross-year credit bleed; boundary re-anchors per year). | **OPEN — track with the rollover / TX-SPLIT Jan-2027 work (canonical roadmap §12.3 / T-1).** The current control is `model_year`-scoped via the snapshot boundary; rollover behavior must be characterized before the first cross-year close. |
| d | **Progress-plane event-ledger treatment** | The eventual "append-only execution/attribution ledger" analogue of `holding_events`, but for the eligible nine — the durable home for (b), if adopted. | **OPEN — candidate, not decided.** Must be designed against the frozen snapshot grant matrix (never re-open G-01…G-08) and may consume 5G-1D persisted state. Owning phase: the L3 ledger that "rides 1B" (roadmap §8/P8), scoped in a future spec. |

## Constraints carried forward

- (b)/(d) must not weaken or re-open the 5G-1D snapshot grant matrix; snapshots remain the authoritative reconciled funded-state mechanism.
- The adapter control (a) is the interim guarantee until (b)/(d) land; it must remain in place and green through activation and until a durable identity supersedes it.
- No amount-only or cross-goal matching in any successor; `fixed_once` (seed) stays separate from target accumulation.

## Pointer

Add to `docs/roadmap/canonical-roadmap.md` as an open identity item (progress-plane transfer identity) referencing this amendment; seed the corresponding decision-log rows (2026-07-15).
