# Roadmap Archive & Provenance Index

**Purpose:** Under the four-document authority model (Law / State / History / Plan), there is exactly **one** live roadmap authority: `docs/roadmap/canonical-roadmap.md` (the **Plan**). This index records the prior roadmap layers as **provenance only** — they are *not* concurrent authorities and must not be cited as sequencing authority. Where any layer below conflicts with the living roadmap, the living roadmap wins. Git history is the changelog; no file is physically moved by this index (the `docs/` reorg is DOC-3, a recorded post-5G-1D action — see the living roadmap §16).

**Authority precedence (highest first):** `AGENTS.md` (Law) + `CODEX_STATUS.md` (State) + cleared 5G-1D scope + Do-Not-Touch + Wendy-confirmed workflow → `docs/roadmap/canonical-roadmap.md` (Plan) → *(archived layers below — provenance only)*.

---

## Superseded roadmap layers (provenance only — do NOT use as sequencing authority)

| Layer | Path / location | Date | Role now |
|---|---|---|---|
| **FINAL roadmap** | `post-5g-1d-canonical-roadmap-final-2026-07-13.md` (planning branch `docs/post-5g-1d-canonical-roadmap` @ `dbc1aee`; Adam's retained copy under `~/Downloads/5G-1D-PostRoadmap-Fable-Review/`) | 2026-07-13 | **Superseded by the living roadmap.** Its P0–P8 macro sequence, decision principles, dependency graph, and lanes were folded in (living §2/§3/§10). Retained for its §0 currency/conflict-resolution table. |
| **Canonical synthesis** | `docs/post-5g-1d-canonical-roadmap-synthesis-2026-07-13.md` | 2026-07-13 | **Superseded.** Retained for its full three-review reconciliation and the §2.4 year-pin inventory (extended by living §14 AF-2). |
| **Prior synthesis** | `docs/post-5g-1d-roadmap-synthesis-2026-07-12.md` | 2026-07-12 | Superseded; provenance. |
| **Calc-core extraction amendment** | `docs/post-5g-1d-roadmap-amendment-calc-core-extraction-2026-07-13.md` | 2026-07-13 | **Normative content folded into the living roadmap §9** (taxonomy + extraction charter + module/test posture + rollover relationship + D10). The amendment file is retained for its Fable-review disposition detail (§8). |
| **Fable independent challenge** | `post-5g-1d-canonical-roadmap-final-fable-challenge-2026-07-13.md` (findings F-01…F-13) | 2026-07-13 | Superseded by the 2026-07-14 adoption review; F-01…F-13 dispositions carried in living **Appendix A**. |
| **Fable Roadmap Adoption Review (controlling external input)** | `Fable — Post-5G-1D Roadmap Adoption Review - 2026-07-14` (Adam's copy; not committed) | 2026-07-14 | **The controlling input adopted by A1.** Its R1–R15, AF-1…AF-10, SR-1…SR-5, and §12 A-list are folded into the living roadmap. Advisory once adopted; the living roadmap is the authority. |
| **Fable Targeted Sequencing Review** | `Fable Targeted Sequencing Review - 2026-07-14.md` (Adam's copy; not committed) | 2026-07-14 | **Controlling input for T-1…T-5** (corrected sequence, rollover-protection, Stage-1A dissolution, BUD-MX fold, TX-SPLIT placement, honest 2027 dates). Folded into living §3.0/§12.3. |
| **Fable Sequencing Amendment — Boundary Clarifications** | `Fable Sequencing Amendment - Boundary Clarifications - 2026-07-14.md` (Adam's copy; not committed) | 2026-07-14 | Amends the targeted review: P3b-1.MX scope, pre-1B bright line (§8), TX-SPLIT swap trigger, original T-6 (AMEX composition rider). Folded into living §3/§8/§12.3. |
| **Fable Sequencing Amendment 2 — Account Composition Scope** | `Fable Sequencing Amendment 2 - Account Composition Scope - 2026-07-14.md` (Adam's copy; not committed) | 2026-07-14 | Amends §1/T-6: **Account Composition Visibility Rider** (AMEX Savings + Truist Savings; Checking deferred to 5G-3; not `5G-3A`). Folded into living **§18** + T-6. |
| **Application-modularization review** | `docs/reviews/application-modularization-review-2026-07-13.md` | 2026-07-13 | Advisory source for the amendment; provenance/architectural detail only. |
| **Strategic roadmap / future horizons** | `docs/strategic-roadmap-future-horizons.md` | 2026-07-01 | Backlog/Horizon provenance; superseded for sequencing by living §15. |
| **Stabilization roadmap spec** | `docs/stabilization-roadmap-spec.md` (TD-numbered items incl. TD-8) | 2026-06-21 | Provenance for TD-items; TD-8 disposition now in living §14 / Appendix B. |
| **Phase status** | `docs/phase-status.md` | living | **Not a roadmap layer** — it is the per-phase gate/status ledger. Its "Authoritative 5G sub-phase roadmap" table and legacy fold-in resolution point to the living roadmap §9; freeze dates corrected in the A6 patch set. |

---

## Reading guide

- **"What are we doing next / in what order?"** → `docs/roadmap/canonical-roadmap.md` only.
- **"What is true in production right now?"** → `CODEX_STATUS.md` (State) + repository facts.
- **"What rule governs this?"** → `AGENTS.md` (Law).
- **"What was executed against production, and when?"** → `docs/execution-ledger.md` (History).
- **"What did Adam decide, and when?"** → `docs/decision-log.md` (History) + living roadmap §12.
- **"Why does the roadmap say what it says?"** → the archived layers above, in date order.

*Provenance index only. No code, SQL, or production/staging change. No file relocated by this index (DOC-3 reorg is a recorded post-5G-1D action).*
