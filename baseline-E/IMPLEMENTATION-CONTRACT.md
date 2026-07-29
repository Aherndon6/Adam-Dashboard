# Baseline E identity predicate — Implementation Contract

**Status: IMPLEMENTED + Mode-2 REMEDIATION COMPLETE (local) — NOT COMMITTED — NOT AUTHORIZED FOR LIVE EXECUTION.**

> **Update 2026-07-29.** rev-6.1 is the FROZEN controlling spec (`docs/baseline-e-identity-predicate-rev-6.1.md`,
> owner-accepted 2026-07-29). The independent Fable **Mode-2 review returned REVISE BEFORE COMMIT**; the
> remediation (H-1/H-2/H-3, isolated residual<0, M1/M6/M7/M8/M9/M10/M11/M19/M23 twins, routing precedence,
> exactly-once reverse manifestation, coverage de-dup + fixed coverage-v1, fail-closed recall, validation
> hardening, legacy over-allocation guard, Unicode 15.1.0 full case fold, synthetic-UUID replacement) is
> complete locally. **137/137 tests pass; all targeted mutations caught. No commit is authorized** until the
> owner reviews the remediation report. Operational HOLD remains active; no live execution / SQL / production
> access / capacity calc / Wendy-IRA result / transfer.

1. **Controlling specification.** The frozen **rev-6.1** Baseline E identity-predicate specification (as
   consolidated and owner-accepted, including the owner-selected `candgen-v1` N-2 values) is the sole
   controlling authority for this implementation. rev-6.1 is not modified by this work.
2. **Byte-for-byte fidelity.** The implementation must be byte-for-byte faithful to the pinned digest
   preimages, domain/version constants (edge **v3**, graph **v3**, authority **v1**), framing rules
   (`lp(x)=u32be(len(utf8(x)))‖utf8(x)`, `int2dec`, `u32be` list counts, ascending lowercase-hex sort), and
   the `candgen-v1` manifest.
3. **No reinterpretation.** No implementation-time reinterpretation or silent specification change is
   permitted. Where rev-6.1 is explicit, the code mirrors it exactly.
4. **Stop on ambiguity.** Any ambiguity or contradiction discovered during coding triggers an immediate STOP
   and owner review — no improvisation.
5. **Rule citation.** Every implemented FAIL-STOP, HOLD, and accepted-disposition path cites its governing
   rev-6.1 section in code comments and in the disposition evidence.
6. **Test provenance.** Every test identifies the exact rev-6.1 clause / control it proves.
7. **No live authorization.** This implementation approval authorizes no live execution, no production/staging
   access, no SQL, no capacity calculation, no Wendy-IRA result, and no transfer. The operational HOLD remains
   active. No commit is created until the owner reviews this report and explicitly authorizes one.

## Module map (rev-6.1 clause → module)
- `src/framing.mjs` — §framing (lp/u32be/int2dec/domain SHA-256), null sentinel `"\x00NULL"`.
- `src/digests.mjs` — canonical_value / anchor_evidence / evidence_root / edge v3 / graph v3 / authority v1 / graph_identity; version enforcement.
- `src/canon.mjs` — anchor canonicalization (N-6), candgen description tokenization, ET day truncation.
- `src/independence.mjs` — evidence-root independence collapse clauses 1–5 (T-c default fail-closed).
- `src/identity.mjs` — IS-1; anchor categories A/B/C; N-1 provenance; "presented as authoritative".
- `src/candgen.mjs` — frozen `candgen-v1` manifest + recall windows (full-horizon, ±14d ET, tokens, boundaries).
- `src/coverage.mjs` — `coverage_horizon_end` endpoint validation + `coverage_sufficient` + cycle counting.
- `src/subject.mjs` — UUID-v4-only subject validation (canonical parse); role disabled.
- `src/allocation-g.mjs` — G acceptance: residual recompute (unconditional `<0` FAIL-STOP), edge/event/graph validation, cross-txn gate, ≥1 evidence root, `allocated≥1`, component-state, reverse-manifestation, digests, authority.
- `src/match.mjs` — orchestrator: candidate generation → identity → A/C/D/E routing with FAIL-STOP precedence; delegates G.
- `src/allocation.mjs` — UNCHANGED (its conservation validator is retained; the unconditional residual<0 guard is enforced in `allocation-g.mjs`/`match.mjs` per rev-6.1 §10).
