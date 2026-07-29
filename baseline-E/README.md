# Baseline E — executable package

**Status: IMPLEMENTED + Mode-2 REMEDIATION COMPLETE (local, uncommitted) — NOT AUTHORIZED TO EXECUTE.** This
package implements the owner-approved Baseline E rev-8 design and the **FROZEN rev-6.1 identity predicate**
(`docs/baseline-e-identity-predicate-rev-6.1.md`, owner-accepted 2026-07-29). The independent Fable **Mode-2
review returned REVISE BEFORE COMMIT**; the remediation is complete locally (**150/150 tests pass; all
targeted mutations caught**). It has **not** been run against production/staging, produced **no** capacity
number and **no** Wendy-IRA result, and **no commit is authorized** until the owner reviews the remediation
report. The operational HOLD remains active.

**Run tests:** `node --test baseline-E/test/*.test.mjs`
**Regenerate the case-fold table:** `node baseline-E/tools/gen-casefold.mjs` (from the pinned
`baseline-E/data/CaseFolding-15.1.0.txt`).

### rev-6.1 remediation modules (added to the earlier construction)
`src/framing.mjs`, `src/digests.mjs`, `src/canon.mjs`, `src/casefold.mjs` + `src/casefold-table-15.1.0.mjs`
(pinned Unicode 15.1.0 full case fold), `src/independence.mjs`, `src/identity.mjs` (IS-1 + H-3),
`src/candgen.mjs`, `src/coverage.mjs`, `src/subject.mjs`, `src/allocation-g.mjs` (G acceptance),
`src/match.mjs` (routing), `tools/gen-casefold.mjs`, `data/CaseFolding-15.1.0.txt`.

## Layout (engineering decisions — recorded for Mode-2 review)
- `baseline-E/` at repo root — keeps the executable package separate from the design docs (`docs/`) and from
  the single-file app (`index.html`). Chosen over polluting `docs/`.
- ESM `.mjs`, **zero external dependencies** (the repo's `node_modules` holds only Playwright, which is not
  used). Tests use Node's built-in `node:test` + `node:assert/strict`.
- `src/` pure logic · `schema/` JSON-Schema contract · `harness/` live-evidence harnesses (live runs pending)
  · `test/` deterministic tests. Fixtures are inlined in the test files (small, self-contained).
- All money is **integer cents** end-to-end (§8); no float arithmetic in any calculation path.

## Run the deterministic suite
```
node --test baseline-E/test/*.test.mjs
```

## Components → design mapping
| File | Design section | Notes |
|---|---|---|
| `src/cents.mjs` | §8, §2 | decimal-string→cents; `events_json` canonicalization (decimal-token preferred; JS-number fail-closed) |
| `src/adapter.mjs` | §0(i), §1a | pure `reconEffectiveWD()` merge; raw rows, no collapse; duplicate detection. **Live override snapshot + differential oracle = authorized-capture step (pending).** |
| `src/calc.mjs` | §9, §10, §12 | two projections, synthetic checkpoint, global trough, gated max-safe + 3-case self-verification |
| `src/allocation.mjs` | §5c, tests 71/79 | `confirmed_matches[]` + allocation-graph **validator** (exact cent conservation; no tolerance). Validates adjudicated input; not a solver. |
| `src/manifest-validate.mjs` + `schema/manifest.schema.json` | §2, §1d, §5, §12 | narrowest schema; `coverage_horizon_end` bound; closed enums only where the design fixes a vocabulary; constrained strings + semantic checks elsewhere |
| `src/match.mjs` | §5c stage B / rev-6.1 §4 | identity-strong predicate + A/C/D/E routing with FAIL-STOP precedence — **IMPLEMENTED** (`IDENTITY_STRONG_PREDICATE_STATUS = 'IMPLEMENTED_REV_6_1'`) |
| `src/identity.mjs`, `src/independence.mjs` | rev-6.1 §3 | IS-1 + H-3 closed anchor vocabulary + provenance-root independence |
| `src/allocation-g.mjs` | rev-6.1 §5 | disposition-G acceptance (H-1 authority, H-2 reconciliation, §10 residual, §12 exactly-once) |
| `src/canon.mjs` + `src/casefold*.mjs` | rev-6.1 §2 | Unicode 15.1.0 full case fold (pinned table) + candgen tokenization + ET day truncation |
| `src/candgen.mjs` / `src/coverage.mjs` / `src/subject.mjs` | rev-6.1 §6/§7/§8 | candgen-v1 recall / coverage-v1 / subject UUID-v4 validation |
| `harness/parity.mjs` | §1e | parity comparison logic + closed difference catalogue; **live parity pending** |
| `harness/rls-proof.mjs` | §1b | four-way visibility reconciliation + evidence contract; **independent live channel pending** |

## Live-evidence gates (deferred to an authorized capture window — NOT run here)
- Adapter differential-oracle validation vs in-app `reconEffectiveWD()` (needs the app + a production override snapshot).
- Parity harness vs the deployed `runModel` (needs production data).
- RLS independent visibility proof (needs a two-role production read via a channel proven independent of the adapter's RLS restriction — the concrete channel is itself a pending §1b design item).

## Status (2026-07-29)
- rev-6.1 is **FROZEN** (`docs/baseline-e-identity-predicate-rev-6.1.md`, owner-accepted 2026-07-29); the
  identity predicate is **implemented locally** and the full **A–K remediation is complete**.
- The targeted independent Fable **delta review found four narrow commit blockers** (recoverable old fixture
  UUID; B5 lenient date parse; candgen manifest presence-only validation; a stale README). **This fix pass
  (rev-6.1a) closes those blockers** and the related before-freeze cleanups.
- The package is **not yet committed** (awaiting owner authorization); **live execution is not authorized**;
  the operational **HOLD remains active**. Tests 69/72/76/77/79 are executing (no `todo`).
