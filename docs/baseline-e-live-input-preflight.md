# Baseline E — Live-Input Preflight (fail-closed admissibility)

**Status: LOCAL, SYNTHETIC, UNCOMMITTED. No network, no SQL, no secrets, no capacity calculation.**
A synthetic PASS does **not** imply live readiness or that any live package was collected. Operational HOLD active.
**All findings CLOSED: 8 original → NEW-A..E → meta-control → NEW-F → section-G source authority** (successive
owner-authorized additive hardening passes 2026-07-30; no adopted control weakened; NEW-C confirmed aligned with
committed state-parity). A **control-flow admissibility invariant (meta-control)** ensures no alternate/skipped/
early-return/caller-supplied path can mark a package admissible before every blocking control has executed. **NEW-F**
(linkage-authoritative dedup identity) and the **section-G source-authority residual** (no self-asserted exemption)
are now closed with executable evidence. A final narrow Fable re-glance follows. **120 fixtures / 41 mutations.**

## Objective / scope / exclusions
Define how a **future** live-evidence package for Baseline E is collected, identified, normalized, validated,
reconciled, deduplicated, attested, rejected-when-incomplete, and packaged — and prove (against synthetic fixtures)
that the preflight **fails closed**. It decides only **admissibility**; it does **not** compute capacity or decide
Wendy-IRA safety. Out of scope (separate authorized gates): live evidence collection, RLS/visibility proof, the
capacity calculation, the Wendy-IRA determination, any transfer. No application code is changed.

## Evidence contract (`live-preflight-v1`)
Input sections A–L (M `preflight_results` is produced by the validator): `package_manifest`, `environment_identity`,
`execution_identity` (subject UUID role-disabled, `as_of_utc`, `evaluation_model_week`, `extraction_window`),
`account_balance_evidence`, `weekly_reconciliation_evidence`, `cash_commitment_evidence`,
`off_model_obligation_evidence`, `register_transaction_evidence`, `pending_or_uncleared_evidence`,
`terminal_resolution_evidence`, `completeness_attestations`, `source_query_manifest`; plus supporting
`baseline_e_adjustments` and `economic_linkages`. Each evidence record carries provenance and a per-record
canonical-JSON SHA-256 digest (P-4 tamper detection — distinct from the frozen rev-6.1 digest scheme). The validator
fails closed on a missing required section, unsupported contract version, or digest mismatch, and — after the
hardening pass — on **query-provenance gaps** and **all-section timestamp** violations.

## Authority hierarchy
Balance basis precedence **reconciled > posted_current_balance > available_balance > projected/stale/unknown/null**
(only the first three authoritative; projected never silently substituted). Obligation authority only via a
`cash_commitment` or explicit `baseline_e_adjustment` **that exists in the package** with matching amount/source.
Economic identity must be **authoritative** (source `expected_item_id`/`economic_event_id` or a validated
`economic_linkages` record) — never a free-text label. Completeness only via `complete`/`verified_empty` +
`attested:true` (+ `rows_visible`/`zero_rows_verified` for verified-empty).

## Controls (`live-preflight-controls.mjs`)
**S-1** material off-model **referential integrity** — every material obligation must resolve to an existing
`cash_commitment` or `baseline_e_adjustment` (amount/source consistent, no dangling/ambiguous/shared/warning-only) ·
**S-2** null/missing/unusable reconciliation chk → HOLD (never zero) · **S-3** duplicate/conflicting reconciliation
(week_num) → FAIL_STOP · **S-4** invalid commitments (amount/status/resolution/contradiction/identity/source/year/
week/clearing) · **S-5** uncleared Register must be reflected-or-deducted; **self-asserted materiality threshold
HOLDs** (none authorized) · **S-6** completeness attestation for **all 8 evidence sections** (status/attested/
rows_visible/rows_returned/zero_rows_verified/query_id/schema/extraction_ts/namespace; verified-empty strict) ·
**S-7** reserve-release evidence — **cross-checks section-F releases (reflected/resolved/terminal) against section-J
typed evidence**, reproducing committed state-parity SP-79 (reflected/resolved release without durable typed
evidence → HOLD; bare `cleared_transaction_id` requires amount+source+state+as_of; orphan J → HOLD).
**P-1** environment certification · **P-2** as-of coherence over **all sections** with **canonical UTC parsing** +
`P2_FRESHNESS_POLICY_NOT_AUTHORIZED` (no freshness tolerance authorized) · **P-3** schema/version · **P-4** evidence
integrity · **P-5** cardinality · **PQ** query provenance (every section tied to a valid manifest entry; required
provenance fields; execution_status=success; env/schema match; no orphan/duplicate/row-count mismatch) · **P-6**
identity uniqueness · **P-7** economic identity (authoritative, not free-text) + no double counting · **P-8** transfer
treatment (exactly two well-formed mirror legs; explicit group id; opposite signs; exactly-equal amounts; **no
near-net tolerance**; no malformed/duplicate/mixed group; no leg deducted elsewhere) · **P-9** authoritative balance
selection · **AN** minimum authoritative checking anchor (≥1 reconciled/posted/available checking balance) · **XC**
cross-control consistency (three-way count reconciliation; a transfer leg cannot also be a pending deduction or a
commitment clearing txn; a self-asserted derived field must match the records it summarizes).

## Admissibility invariant
`package_admissible = required_sections_present AND every control === PASS`. A HOLD/FAIL_STOP can **never** be promoted
to PASS (proven by PF-40 + mutation MUT-14).

## Eight Fable findings → closures (owner-ruled 2026-07-30)
| # | Finding | Closure | Proof |
|---|---|---|---|
| HIGH | S-7 F-section gap (conflicted with state-parity SP-79) | S-7 now cross-checks F releases vs J typed evidence; cleared_txn requires full metadata | PF-41..47, MUT-15/16 |
| HIGH | S-1 referential gap | S-1 requires the referenced commitment/adjustment to exist (amount/source consistent) | PF-48..53, MUT-17 |
| MED-HIGH | S-5 self-asserted threshold | unauthorized threshold → HOLD (no artifact authorized) | PF-54/55, MUT-18 |
| MED | minimum anchor | AN control requires ≥1 authoritative checking anchor | PF-56..59, MUT-19 |
| MED | S-6 coverage | all 8 sections attested; verified-empty strict (rows_visible + zero_rows_verified) | PF-60..64, MUT-20/21 |
| MED | P-8 transfer edges | exactly-two mirror legs, explicit group id, no near-net, no malformed group | PF-65..69, MUT-22/23 |
| MED | P-7 rename dodge | authoritative economic identity required; free-text HOLDs | PF-70..73, MUT-24 |
| OPEN | query provenance + P-2 coverage | PQ wired; P-2 covers all sections with canonical-UTC parsing + freshness HOLD | PF-74..80, MUT-25/26 |
| + | cross-control consistency | XC layer added | PF-81, MUT-27 |

## Fixture inventory — 120 synthetic PF-01..PF-120
PF-01..40 original classes; PF-41..47 S-7 cross-consistency; PF-48..53 S-1 referential; PF-54..55 S-5 threshold;
PF-56..59 anchor; PF-60..64 S-6 coverage; PF-65..69 P-8 transfers; PF-70..73 P-7 identity; PF-74..80 provenance/P-2;
PF-81 cross-control; PF-82..87 NEW-A duplicate-relation; PF-88..91 NEW-B materiality; PF-92..96 NEW-C liveness;
PF-97..101 NEW-D integrity; PF-102..104 NEW-E within-path; PF-105..115 NEW-F linkage identity; PF-116..120 section-G
source authority. **20 admissible / 100 rejected, 0 mismatches.**

## Mutation inventory — 41 executable (`run-live-preflight.mjs`)
MUT-01..27 (original + 8-finding hardening) + MUT-28..32 (NEW-A..E) + MUT-33..37 (meta: skip-control,
early-return-before-XC, caller-supplied, duplicate/unknown control result) + MUT-38..41 (NEW-F local-row-id fallback,
section-G trust-affects-false / trust-completed, permit-ambiguous-linkage). Each disables one control and flips its
fixture NOT-ADMISSIBLE→ADMISSIBLE through `validatePackage`, deterministic; **all
27 caught**; none analytic/tautological (MUT-14 stubs the aggregator to prove the HOLD-never-PASS invariant).

## Machine-readable fields (`live-preflight-results.json`)
`fable_verdict`, `open_findings=[]`, `all_fable_findings_closed=true`, `state_parity_s7_consistent`,
`release_evidence_referentially_complete`, `off_model_references_resolved`, `unauthorized_threshold_paths_closed`,
`authoritative_checking_anchor_present`, `all_required_sections_attested`, `verified_empty_semantics_enforced`,
`transfer_groups_well_formed`, `economic_identity_authoritative`, `query_provenance_complete`,
`all_timestamps_validated`, `as_of_coherent`, `freshness_policy_authorized=false`,
`cross_control_consistency_verified`, `executable_mutation_coverage_complete=true`, `package_admissible` (golden
only), **`capacity_calculation_eligible=false`**, **`obligation_set_complete=false`**, `synthetic_only=true`,
`live_access_performed=false`, `sql_executed=false`, `operational_hold=true`, `blocking_controls`, `control_results`,
`fixture_totals`, `mutation_totals`, `remaining_blockers`.

## Threshold & economic-identity policy decisions
- **Materiality threshold:** none authorized. A self-asserted `immaterial_under_authorized_threshold` HOLDs. A future
  threshold pass requires a versioned, integrity-protected authorization artifact (id, amount+currency, scope,
  effective date, approving authority, contract/schema version, digest, applicable classes) explicitly linked from
  the exempted item — **not invented here**.
- **Economic identity:** authoritative source id or a validated `economic_linkages` record only; labels/descriptions
  are supporting evidence but cannot establish identity; absent authoritative identity → HOLD.

## Re-review escapes NEW-A..E — CLOSED (owner-authorized final hardening 2026-07-30)
| # | Escape | Closure | Proof |
|---|---|---|---|
| NEW-A | duplicate-relation manifest entries reconciled only on the first | PQ enforces exactly one authoritative entry per relation (no partition contract); conflicting count/scope/digest → FAIL_STOP | PF-82..87 + MUT-28 |
| NEW-B | self-asserted `material:false` bypasses S-1 | materiality is not a self-asserted exemption; only an authoritative `affects_deployable_cash:false` exempts; else a deduction is required | PF-88..91 + MUT-29 |
| NEW-C | S-1 lacks deduction liveness | S-1 proves the referenced commitment/adjustment still **reserves** (mirrors state-parity `isReservedAsOf`: not voided/released/reflected/inactive) | PF-92..96 + MUT-30 |
| NEW-D | P-4 excludes non-evidence sections | P-4 extends whole-section digests to `baseline_e_adjustments`/`economic_linkages`/`completeness_attestations`/`source_query_manifest` + package fields | PF-97..101 + MUT-31 |
| NEW-E | P-7 double-count cross-path only | P-7 now rejects any repeated authoritative economic identity (within-path too) | PF-102..104 + MUT-32 |

## NEW-F + section-G source authority — CLOSED (owner-authorized final hardening 2026-07-30)
- **NEW-F CLOSED (for the disclosed defect).** P-7 derives a linkage-authoritative deduction's dedup identity from
  the **authoritative linked target** (`namespace:target_id`) rather than the deduction's own local **source** row id.
  Resolution order: direct `economic_event_id` (`event:<id>`) → validated `economic_linkages` target → declared
  aggregation contract → else HOLD (`P7_LINKAGE_AUTHORITATIVE_IDENTITY_REQUIRED`). Commitment identity is
  `commitment:<expected_item_id>`, so a pending/adjustment linked to a commitment collides with it (cross-path), and
  two deductions resolving to the same target collide (within-path → `P7_LINKAGE_WITHIN_PATH_DOUBLE_COUNT` /
  `P7_DUPLICATE_LINKED_ECONOMIC_EVENT`). Linkage validation: complete fields, valid cardinality, **trivial self-cycle**
  rejected, no ambiguous/conflicting target (`P7_LINKAGE_TARGET_AMBIGUOUS`), no duplicate linkage
  (`P7_DUPLICATE_LINKAGE`). Fixtures PF-105..PF-115, mutations MUT-38/41.

### RG-1..RG-6 linkage-graph residuals — CLOSED (owner-authorized additive pass 2026-07-30)
The prior narrow re-glance (verdict 2) confirmed NEW-F + section-G authority closed but disclosed a residual
**linkage-graph** family. The owner authorized an additive pass closing all six; every closure preserves fail-closed
behavior and adds no self-asserted, package-builder, or inferred path.
1. **RG-1 — closed namespace vocabulary.** A linkage source must be a local deduction row (`adjustment`/`pending`) and
   a target must be an authoritative economic identity (`event`/`commitment`); anything else (e.g. `evt`) → HOLD
   (`P7_LINKAGE_SOURCE_NAMESPACE_UNKNOWN` / `P7_LINKAGE_TARGET_NOT_AUTHORITATIVE`). Fixtures PF-121/PF-122, MUT-42.
2. **RG-2 — event/commitment identity unified.** Deductions dedup on `econKey` (both `event:X` and `commitment:X`
   collapse to `econ:X`), so a direct `economic_event_id` equal to a commitment `expected_item_id` collides.
   Fixture PF-123, MUT-43.
3. **RG-3 — no graph indirection.** Any linkage target that is itself a linkage source (chains A→B→C, 2-cycles) →
   HOLD `P7_LINKAGE_GRAPH_INDIRECTION`; the vocabulary split makes indirection structurally impossible and the guard
   is defense-in-depth (isolated by MUT-44 / the RG-3 unit test with vocab bypassed). Fixture PF-124.
4. **RG-4 — target must be authoritative, never a local row.** A target in `{adjustment, pending}` (another
   deduction's local row) fails the target-vocabulary check → HOLD. Fixture PF-125, MUT-45.
5. **RG-5 — `declared_aggregations` REMOVED.** No self-asserted aggregation exemption remains in P-7; a duplicate
   deduction always fails closed even if the package declares an aggregation. Fixture PF-126 (exemption present but
   ignored). No replacement inferred/heuristic path was added; an aggregation contract, if ever needed, is a separate
   owner authorization.
6. **RG-6 — dedicated unsupported-field code.** A section-G obligation carrying a field outside the recognized schema
   (with no authoritative path) → HOLD `S1_UNSUPPORTED_AUTHORITY_FIELD` (still fail-closed; no unknown field grants an
   exemption). Fixture PF-118.

Identity scope note: a linkage-authoritative deduction's dedup identity is the deduction's own **source** row id
resolved to its authoritative target; the **target** is constrained to an authoritative economic identity (RG-4), so
row-id identity cannot be reintroduced through the target side either.

### OBS-5 identity-resolution bypasses — CLOSED (owner final scoped correction 2026-07-30)
The RG-1..RG-6 re-glance returned APPROVE WITH NON-BLOCKING CONDITIONS with **OBS-5** as its one not-yet-accepted
condition: orphan linkages, empty/whitespace identities, and targets not verified to exist. These were
identity-resolution bypasses in the P-7 linkage graph (conservative in direction, but the preflight must never treat an
arbitrary, empty, or nonexistent target as an authoritative economic identity). All are now closed; every check runs
**before** namespace construction, comparison, hashing, or graph traversal.
- **Identity validation.** Every linkage `source_id` / `target_id` (and each commitment `expected_item_id` used to build
  an identity) must be a **non-empty, non-whitespace, control-character-free scalar string**. `null`/`undefined`/empty
  → `P7_LINKAGE_SOURCE_ID_MISSING` / `P7_LINKAGE_TARGET_ID_MISSING`; wrong type / control chars →
  `..._ID_INVALID`. No invalid value is normalized into a valid identity; no `event:`/`commitment:`/`adjustment:`/
  `pending:` with an empty suffix is ever constructed. Fixtures PF-128..PF-131.
- **Source existence.** A linkage `source_namespace:source_id` must resolve to exactly one deduction record in the
  package (a `pending` txn or `adjustment` row); otherwise `P7_LINKAGE_SOURCE_NOT_FOUND`. Fixture PF-132.
- **Authoritative-target existence.** A `commitment` target must resolve to exactly one `expected_item_id`
  (`P7_LINKAGE_COMMITMENT_NOT_FOUND` if none; `P7_LINKAGE_TARGET_AMBIGUOUS` if >1, with P-6 identity-uniqueness as the
  first-line FAIL_STOP). An `event` target must be **independently established** by some record carrying that direct
  `economic_event_id` — the linkage's own target string is never proof (`P7_LINKAGE_EVENT_NOT_ESTABLISHED`). A target
  that exists only in an unknown top-level section is **not** established (the authoritative universe is built only from
  known sections). Fixtures PF-133/PF-134/PF-139 (HOLD), PF-135/PF-140 (valid, established event target),
  PF-136/PF-137 (commitment resolution + ambiguity).
- **Orphan linkages.** Every linkage must be **consumed** by a real deduction whose source resolves through it; an
  unconsumed linkage is never silently ignored → `P7_ORPHAN_LINKAGE`. Fixture PF-138.
- **PF-115 correction.** PF-115 previously admitted a linkage whose event target (`T1`) was referenced **only by the
  linkage itself** — i.e. an unestablished target. It is now a genuinely valid fixture: its target is established by a
  non-deducting `estab()` record carrying the direct `economic_event_id`. (The same `estab()` establishment was added
  to the other event-target NEW-F fixtures so their double-count / distinct-target semantics are exercised against a
  target that genuinely exists.)
- **Independent RG-3 proof.** The graph-indirection guard is now **namespace-agnostic** (no id token may be both a
  linkage source and a linkage target — chains, 2-cycles, shared-token indirection). PF-127 expresses a
  **namespace-valid** shared-token indirection: the guard fires (`P7_LINKAGE_GRAPH_INDIRECTION`) with vocabulary
  validation fully **active**, and toggling only `allowGraphIndirection` changes the outcome — proving the guard is
  load-bearing independently of the namespace vocabulary (not a compound-mutation artifact).
- **Mutations.** Clean flip-to-admissible coverage: MUT-46 (orphan), MUT-47 (trust event target), MUT-48 (ignore
  commitment existence). Attribution proofs (guard bypass changes the reason, package stays inadmissible via a deeper
  guard): empty source/target id, source existence, and the isolated RG-3 guard — asserted in the unit suite. The
  prior compound RG-3 mutation was removed in favor of the independent proof.

Commit-readiness note: the earlier statement that "the P-7 identity area has no remaining bypass" was **premature** —
OBS-5 was still open at that time. With OBS-5 closed and independently verified, `all_p7_identity_bypasses_closed=true`.
- **Section-G source authority CLOSED.** The prior `affects_deployable_cash:false` self-exemption is **removed**: no
  self-asserted section-G value (package-builder `affects_deployable_cash:false`, source/package `material:false`,
  `completed:true`, or any unsupported claimed field) exempts an obligation — every section-G obligation must resolve
  to a **live authoritative deduction** or HOLD (`S1_UNSUPPORTED_CASH_IMPACT_CLASSIFICATION` /
  `S1_SELF_ASSERTED_IMMATERIALITY` / `S1_OFF_MODEL_DEDUCTION_REQUIRED` / `S1_MATERIALITY_UNRESOLVED`). No authoritative
  non-cash field or policy artifact is authorized. Fixtures PF-116..PF-120, mutations MUT-39/40 (+ MUT-29). Digest
  protection proves the packaged value was not altered — **not** that it came from an authoritative source; hence no
  self-asserted exemption is honored.

## Control-flow admissibility invariant (meta-control)
`package_admissible=true` is derived **only** from the complete control-result set: a required-control registry
(`REQUIRED_CONTROL_IDS`) is checked for **every control executed exactly once**, no missing/duplicate/unknown result,
and no HOLD/FAIL_STOP. The validator never trusts a caller-supplied admissibility field or a HOLD-promotion. Reason
codes: `META_REQUIRED_CONTROL_MISSING`, `META_DUPLICATE_CONTROL_RESULT`, `META_UNKNOWN_CONTROL_RESULT`. Mutations
MUT-33..37 prove a skipped control, an early return before XC, a caller-supplied admissibility, and injected
duplicate/unknown control results are all caught. Machine-readable: `required_control_ids`, `executed_control_ids`,
`missing_control_ids`, `duplicate_control_ids`, `unknown_control_ids`, `all_required_controls_executed`,
`control_flow_complete`, `admissibility_derived_only`, `alternate_success_path_detected`.

## Fail-closed behavior & residual limitations
The preflight fails closed on modeled AND previously-unmodeled paths (F-section releases, unresolved/non-live
authority references, self-asserted immateriality/materiality, absent anchors, unattested sections, malformed/near-net
transfers, free-text/within-path identity duplication, missing provenance, duplicate-relation manifests, out-of-
window/non-UTC timestamps, cross-control contradictions, and any skipped/duplicate/unknown/alternate control-flow
path, plus empty/whitespace/malformed identities, unresolved linkage sources, unestablished/nonexistent targets, and
orphan linkages). **140 fixtures (20 admissible / 120 rejected, 0 mismatches); 47 executable mutations, all caught.**
Residuals: (1) **synthetic only** — admissibility proves the *validator*, not a real package; (2)
`obligation_set_complete=false` (reflects the live load); (3) any attestation scheme ultimately trusts the extractor's
`rows_visible`/`zero_rows_verified` assertion — the live gate's **RLS/visibility proof** must make that assertion
verifiable; (4) no freshness-vs-now policy is authorized (fails closed via `P2_FRESHNESS_POLICY_NOT_AUTHORIZED`).

Remaining **non-blocking** identity observations (OBS-5 now CLOSED; these are conservative or inert, none
capacity-overstating): **OBS-1** RG-2 closes literal `event:X`/`commitment:X` equality only — distinct id *strings* are
distinct events absent an authoritative event registry (understating). **OBS-2** a legitimate many-to-one split-payment
aggregation is inexpressible (over-blocking, intended by RG-5). **OBS-3** cross-id-space textual collision over-blocks
(intended by the one-id-space ruling). **OBS-4** unknown top-level sections ride unhashed but are **inert** — the
authoritative identity universe is built only from known sections, so an unknown section can neither establish an event
nor be read by any control; a section allowlist would close the class. The OBS-5 re-glance surfaced two more, both
non-blocking and neither capacity-overstating: **R-1** (inert/consistency) a linkage whose source carries a direct
`economic_event_id` *different* from the linkage target is validated but never applied (resolution prefers the direct
id) and is marked consumed because the source row is a deduction — count-preserving; suggested tightening is a
`P7_LINKAGE_DIRECT_ID_CONFLICT` HOLD. **R-2** (understating) Unicode format characters (e.g. U+200B) pass `isValidId`,
so visually-twin ids count as two distinct events (the OBS-1 id-hygiene family); establishment still requires an
exact-match real record, so no phantom target is ever established. These six (OBS-1..OBS-4, R-1, R-2) are documented
limitations only, not implemented changes.

## Boundary — local proof vs future live collection · next authorization
This gate delivers the contract + validator + synthetic proof only. The future live gate must: produce a real package
via an **authorized read-only extraction**, record operator project confirmation, and prove RLS/visibility (verified-
empty vs no-rows-visible). Only an admissible **real** package unlocks the subsequent (separately authorized)
capacity-calculation gate. `capacity_calculation_eligible` remains **false**. **Next authorization:** the live-evidence
collection gate.
