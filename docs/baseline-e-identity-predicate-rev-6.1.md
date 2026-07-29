# Baseline E — Identity-Matching Predicate — FROZEN Specification rev-6.1

**STATUS: FROZEN.** Owner-accepted. **Acceptance date: 2026-07-29.**
This is the controlling normative specification for the Baseline E §5c identity-matching predicate and its
disposition A/C/D/E/G routing, digest scheme, canonicalization, candidate generation, coverage, and authority
model. **Any implementation change requires a new specification revision** — this document must not be
silently rewritten or "improved." Transcribed faithfully from the owner-accepted rev-6.1 record (base rev-6.1
+ owner §C/§D selections + §A/§B corrections + the casefold and coverage rulings of 2026-07-29).

Governance context: this predicate is one component of Baseline E. **No live execution, checking-capacity
calculation, Wendy-IRA result, or transfer is authorized by this document.** The operational HOLD remains
active. The local implementation exists (`baseline-E/`); the independent Fable **Mode-2 review returned
REVISE BEFORE COMMIT**; this frozen spec + the remediation address those findings; **no commit is authorized**
until the owner reviews the remediation report.

---

## 1. Digest scheme (byte-for-byte)

**Framing.** `lp(x) = u32be(len(utf8(x))) ‖ utf8(x)` (x a non-empty string, or the null sentinel below;
`undefined`/`null` for a required field is rejected — no `String()` coercion). `int2dec(n)` = canonical
decimal for a non-negative integer: no leading `+`, no leading zeros except `"0"`, negative-zero normalized to
`"0"`. `u32be` = 4-byte big-endian count. Domain tags are raw prefixes consumed first. All hex is **lowercase**.
Null sentinel for `*_or_null` fields = the fixed bytes `\x00NULL` (0x00,0x4E,0x55,0x4C,0x4C).

**Dependency chain (strictly acyclic):** `edge_digest v3` → `allocation_graph_digest v3` →
`allocation_authority_digest v1`. The edge preimage binds **only edge-local facts** and excludes the graph
digest, the authority digest, and all authority fields. Authority binds the graph **as a whole** (via
`allocation_graph_digest`), never per edge; any edge change transitively invalidates graph and authority.

**Version constants (immutable this generation):** `edge_schema_version="v3"`, `graph_schema_version="v3"`,
`authority_schema_version="v1"`, `provenance_version="prov-v1"`, `candidate_generation_version="candgen-v1"`,
`component_schema_version="component-v1"`, `framing_version="framing-v1"`, `routing_rule_version="routing-v1"`,
`subject_id_format_version="subjid-v1a"`, `coverage_policy_version="coverage-v1"`. `canonicalization_version`
= `canon-v1|nfc|casefold:unicode-15.1.0|src-sha:<first16>|gen:casefold-gen-v1|rules:anchor-canon-v1`.
Version rationale: edge→v3 and graph→v3 because their preimages changed (component-state fields added; edge
authority binding removed); authority stays v1 because its preimage structure is unchanged (it takes the v3
graph digest as an opaque input). No v2 digest vector may be accepted as v3.

**Preimages** (SHA-256 over the domain tag ‖ framed fields, lowercase hex):
- `canonical_value_digest` = SHA-256(`"BASELINE-E:CANONICAL-VALUE:v1"` ‖ u32be(len) ‖ canonical_value_bytes) —
  value only; no anchor type / source / provenance. Same normalized value ⇒ same digest across systems/types.
- `anchor_evidence_digest` = SHA-256(`"BASELINE-E:ANCHOR-EVIDENCE:v1"` ‖ lp(anchor_type) ‖ lp(category) ‖
  lp(source_system) ‖ lp(source_field) ‖ lp(canonical_value_digest_hex) ‖ lp(canonicalization_version)) —
  value×role×source; **never** used for independence.
- `evidence_root_digest` = SHA-256(`"BASELINE-E:EVIDENCE-ROOT:v1"` ‖ lp(source_system) ‖
  lp(source_record_digest) ‖ lp(source_field) ‖ lp(derivation_method) ‖ lp(canonical_value_digest_hex) ‖
  lp(anchor_evidence_digest_hex) ‖ lp(provenance_version)) — provenance root; used for independence, derivation
  references, edge binding.
- `edge_digest v3` = SHA-256(`"BASELINE-E:ALLOCATION-EDGE:v3"` ‖ lp("v3") ‖ lp(bank_transaction_id) ‖
  lp(bank_transaction_content_digest_hex) ‖ lp(event_id) ‖ lp(event_content_digest_hex) ‖
  lp(int2dec(allocated_amount_cents≥1)) ‖ lp(edge_direction) ‖ lp(reflected_component_id) ‖
  lp(reflected_component_content_digest_hex) ‖ lp(int2dec(reflected_component_amount_cents)) ‖
  lp(reflected_component_state) ‖ lp(reflected_direction) ‖ lp(remaining_forward_component_id) ‖
  lp(remaining_forward_component_content_digest_hex) ‖ lp(int2dec(remaining_forward_component_amount_cents≥0)) ‖
  lp(remaining_forward_component_state) ‖ lp(int2dec(original_event_amount_cents)) ‖
  u32be(count(sorted_unique_evidence_root_digests≥1)) ‖ each lp(evidence_root_digest_hex) ascending). Duplicate
  or zero evidence roots ⇒ FAIL-STOP before hashing.
- `graph_identity` = SHA-256(`"BASELINE-E:GRAPH-IDENTITY:v1"` ‖ lp("v3") ‖ lp(bank_transaction_id) ‖
  lp(bank_transaction_content_digest_hex) ‖ lp(graph_direction) ‖ u32be(count events) ‖ each
  (lp(event_id) ‖ lp(event_content_digest_hex)) sorted by (event_id, content_digest) ‖
  lp(allocation_generation_or_adjudication_id_or_null)). The gen/adjudication id is a tagged union
  `generation:<64-hex>` | `adjudication:<64-hex>` | null-sentinel; null only when the graph is deterministically
  generated with no separate adjudication/generation record.
- `allocation_graph_digest v3` = SHA-256(`"BASELINE-E:ALLOCATION-GRAPH:v3"` ‖ lp("v3") ‖ lp(graph_identity_hex) ‖
  lp(bank_transaction_content_digest_hex) ‖ lp(graph_direction) ‖ lp(int2dec(bank_posted_amount_cents)) ‖
  lp(int2dec(total_allocated_amount_cents)) ‖ lp(graph_conservation_state) ‖ u32be(count sorted-unique
  edge_digests) ‖ each lp(edge_digest_hex) ascending). Binds the canonical serialized sorted-unique edge_digest
  **values**, not edge objects. Duplicate edge digest ⇒ FAIL-STOP.
- `allocation_authority_digest v1` = SHA-256(`"BASELINE-E:ALLOCATION-AUTHORITY:v1"` ‖ lp("v1") ‖
  lp(authority_kind∈{owner,authoritative_record}) ‖ lp(subject_or_role_id) ‖
  lp(authority_record_digest_or_null) ‖ lp(approved_at_ts_utc) ‖ lp(allocation_graph_digest_hex)).
  Canonical UTC = RFC-3339 `YYYY-MM-DDTHH:MM:SS.sssZ`, validated **semantically** (must be a real instant that
  round-trips). `authoritative_record` kind requires a real record digest; null there ⇒ FAIL-STOP.

**T-a known-answer conformance (normative).** Every digest has published preimage bytes + an expected
lowercase SHA-256 derived **independently** of the implementation under test (external tool over hand-built
preimage bytes). A vector mismatch is an integrity failure that blocks acceptance. The implementation must not
mint its own oracle. ≥1 vector uses NFC-sensitive non-ASCII input.

## 2. Canonicalization (N-6) + case folding (owner Option-1, 2026-07-29)

- **`canonicalization_version`** binds the pinned case-fold provenance so a runtime ICU/Unicode change cannot
  silently alter folding. NFC uses the runtime (stable by Unicode normalization-stability policy).
- **Case folding = Unicode 15.1.0 FULL case folding**, statuses **C (common) + F (full)**, excluding **S**
  (simple-only) and **T** (Turkic). Locale-independent. **Not** `String.prototype.toLowerCase()`, **not** simple
  folding. Implemented from a repository-pinned table generated from the authoritative CaseFolding.txt.
  - Source: `https://www.unicode.org/Public/15.1.0/ucd/CaseFolding.txt`, retrieved 2026-07-29, committed at
    `baseline-E/data/CaseFolding-15.1.0.txt`, **source SHA-256
    `4e55acfdc32825a22e87670e9056a3bf94ad7c5400065778e9e10f8314372bcf`** (84,870 bytes; header Unicode 15.1.0).
  - Generator: `baseline-E/tools/gen-casefold.mjs` (`casefold-gen-v1`); regenerate with
    `node baseline-E/tools/gen-casefold.mjs`. **Generated table SHA-256
    `e0afcc453a580d33ed19fc1c5ac1014cc6271210ba626d9ac8df0219487e727f`** (1426 C + 104 F; 31 S + 2 T excluded).
  - "casefold" MEANS Unicode full case folding; conformance vectors: `ẞ`/`ß`→`ss`, `ſ`→`s`, `ﬀ`→`ff`, `ﬃ`→`ffi`,
    `I`→`i`, `i`→`i`, `İ`→`i̇` (default non-Turkic F), `ı`→`ı` (unchanged), plus an NFC precomposed/decomposed pair.
- **Description tokenization** `unicode_ws_split_nfc_casefold_exact_v1`: NFC → full case fold → split on Unicode
  whitespace → drop empties. No punctuation strip, stemming, fuzzy, transliteration, Turkic folding, or
  post-fold normalization. Exact-token containment. **Category-C recall only; never IS-1.**
- **Anchor canonicalization:** reference/id anchors (A1–A4) = NFC + outer trim only (no fold, no punctuation
  strip, leading zeros preserved). B3 counterparty (structured field only) = NFC + trim + inner-ws collapse +
  full case fold; description-parsed counterparty is Category C, not B3. B4 classification = exact vocabulary
  token. B5 expected-date identity = inclusive interval of canonical valid date/time values (never alone).
  Malformed/ambiguous ⇒ no qualifying anchor.

## 3. IS-1 + H-3 anchor vocabulary + N-1

**Closed anchor-type → category vocabulary (H-3).** Category is **derived from type**; a caller-declared
category that disagrees is a FAIL-STOP. **Amount and direction can never be anchors.**
- **Category A** (content-bound/externally-stable): `bank_reference`, `trace_reference`,
  `content_bound_external_reference`, `recurring_series_identity`, `source_system_identity`.
- **Category B** (supporting; never sufficient alone): `source_account_identity`,
  `destination_account_identity`, `counterparty_identity`, `event_classification`, `expected_date_identity`.
- **Category C** (recall-only; never IS-1): `description_token`, `date_proximity`, `model_week_proximity`,
  `classification_similarity`, `ordinal_position`.
- Unknown type, prohibited type (amount/direction), or incompatible type/category ⇒ FAIL-STOP.

**IS-1 (identity-strong).** ≥2 qualifying A/B anchors, in ≥2 **provenance-root** independence groups, ≥1 of
which is Category A. Independence uses `evidence_root_digest` with the closed collapse set (equal
`canonical_value_digest`; equal `evidence_root_digest`; same source_record_digest+source_field; one
`derivation_method` references the other's `evidence_root_digest`; cross-system replication of equal value —
fail-closed default = collapse). Amount/direction are validated only **after** identity classification.

**N-1 (provenance).** A non-`direct_read` anchor must reference the originating `evidence_root_digest`
(`copied_from:` / `transform_of:` / `parsed_from:<64-hex>`) to count toward IS-1. An anchor **presented as
authoritative** (counted toward IS-1, supporting an accepted A/D/G, a qualifying edge evidence root, a retained
schedule mutation, or represented as confirmed) without provenance ⇒ FAIL-STOP; otherwise it routes to C/HOLD.

## 4. Disposition routing (A/C/D/E/G) + FAIL-STOP precedence

Precedence **FAIL-STOP ≻ C/HOLD ≻ accepted (A/E/G)**. Global config FAIL-STOP conditions are evaluated **before**
any accepted disposition and cannot be masked by A/E/C:
1. N-1 authoritative-without-provenance ⇒ FAIL-STOP.
2. H-3 anchor-vocabulary violation ⇒ FAIL-STOP.
3. `endpoint_ok === false` ⇒ FAIL-STOP (`ENDPOINT_INVALID`). `candgen_valid === false` ⇒ FAIL-STOP
   (`CANDGEN_INVALID`).
4. identity-strong candidate with amount/direction conflict ⇒ **D / FAIL-STOP** (test 76).
5. >1 identity-strong (no approved graph) ⇒ **C / HOLD** (test 69).
6. exactly one identity-strong + consistent (weak candidates recorded) ⇒ **A**.
7. ≥1 plausible, zero identity-strong ⇒ **C / HOLD** (test 72).
8. zero candidates: `candidates_exhaustive !== true` ⇒ **C / HOLD** (E prohibited); else
   `coverage_sufficient !== true` ⇒ **COVERAGE-HOLD** (E prohibited, transfer routes to coverage HOLD);
   else ⇒ **E** (test 77; balance-only, retained schedule byte-identical).

Insufficient-but-valid coverage is **COVERAGE-HOLD**, distinct from invalid endpoint/config which is FAIL-STOP.
An independently-proven A/D/G on a specific transaction remains valid under coverage HOLD.

## 5. Disposition-G acceptance (multi-event allocation)

**H-2 graph-identity reconciliation.** The participating event set is derived from the edges (unique event_id →
event_content_digest, conflict-checked); a presented `graph_identity_events` set must equal it exactly
(phantom, omitted, duplicate, or content-digest mismatch ⇒ FAIL-STOP). graph_identity + graph digest are
computed from the reconciled set. **H-1 authority binding (fail-closed, no truthiness escape).** `bound_graph_digest`
required and must equal the recomputed graph digest; presented `allocation_authority_digest` required and must
equal the recomputed authority digest; invalid subject / kind / semantic-UTC / stale-graph ⇒ FAIL-STOP.
**N-3 recompute-never-trust:** total allocated, residual, all digests, and completeness are recomputed; any
stored-vs-recomputed mismatch ⇒ FAIL-STOP. G is accepted **iff all**:
1. every allocated event independently satisfies IS-1 (N-4 — the graph never waives identity; weak ⇒ C/HOLD);
2. edge-level: `allocated == reflected`, `edge_direction == graph_direction == bank_direction ==
   reflected_direction`; `allocated ≥ 1`; ≥1 evidence root; distinct component ids; component-state consistent
   (zero remaining ⇒ `zero_terminal_remainder`; positive ⇒ `active_remainder`);
3. event-level conservation: `reflected + remaining == original`, `remaining ≥ 0`, `reflected ≤ original` (T-b);
4. **§10 residual**: `residual = posted − Σ allocated`; `residual < 0` ⇒ **FAIL-STOP unconditional** (never
   trusts allocation_complete); `residual > 0` ⇒ **C/HOLD** (incomplete — never G, never E); `residual == 0` ⇒
   proceed; presented total / allocation_complete inconsistency ⇒ FAIL-STOP;
5. cross-transaction: every edge binds the graph's bank transaction id + content digest (T-f); an event in >1
   edge ⇒ FAIL-STOP (§5c F);
6. digests recompute (edge/graph/authority) and match presented (N-3);
7. authority valid + graph-scoped (H-1);
8. **§12 exactly-once reverse manifestation**: each participating event has exactly one valid manifestation;
   zero ⇒ FAIL-STOP; duplicate/orphan/amount-mismatch ⇒ FAIL-STOP;
9. T-d: a fully-reflected event (`zero_terminal_remainder`) may not retain a forward cash effect ⇒ FAIL-STOP.
The legacy `allocation.mjs` conservation validator is unconditionally fail-closed on over-allocation (item K).

## 6. candgen-v1 (frozen; owner §C/§D)

`date_proximity_days=14` (±14 ET calendar days, inclusive, recall-only); `model_week_proximity=full_retained_horizon`
(every in-horizon event is always a candidate; distance never excludes); `expected_date_interval=authoritative_event_window_inclusive`
(B5 only with a content-bound authoritative interval; never alone); `description_token=unicode_ws_split_nfc_casefold_exact_v1`;
`window_boundaries=inclusive_inclusive`; `day_truncation=America/New_York:local_calendar_date:v1` (IANA tz;
DST via the tz database; local-date comparison). **Fail-closed recall (item I):** an event with unknown/malformed
`in_retained_horizon` sets the search non-exhaustive (E prohibited) and is never silently dropped. Missing /
mismatched / unversioned candgen manifest ⇒ prohibits E, routes ambiguous to C/HOLD, FAIL-STOP if an accepted
result falsely represents the config as complete.

## 7. coverage-v1 (owner-approved) + coverage_horizon_end

`coverage_horizon_end` = the **authoritative loaded projection endpoint** (current generation = model week 31,
validated against the loaded snapshot; mismatch ⇒ FAIL-STOP); **never moved** to manufacture sufficiency.
`coverage_policy = { min_model_weeks: 8, min_paycheck_cycles: 2, min_card_statement_cycles: 2 }`,
`coverage_policy_version="coverage-v1"`, **non-overridable** by callers. `coverage_sufficient` iff the inclusive
interval [measurement_start_week … coverage_horizon_end] contains ≥8 weeks and ≥2 unique applicable paycheck
occurrences and ≥2 unique applicable card-statement occurrences. Cycles are **schedule-derived and de-duplicated
by content-bound `occurrence_id`** (duplicates do not inflate; irrelevant events do not count; missing
`occurrence_id` ⇒ FAIL-STOP). measurement_start_week = the transfer week (else as_of_model_week). Insufficient
coverage ⇒ E prohibited + coverage HOLD; independently-proven A/D/G remain valid.

## 8. subject_or_role_id (subjid-v1a)

Tagged union: **`user:<canonical-lowercase-uuid-v4>` only** this generation; `role:<…>` disabled (deferred).
UUID v4 validated by canonical parse (version nibble 4; RFC-4122 variant `8|9|a|b`; lowercase hyphenated;
round-trip equality). Max 128 bytes; NFC; no whitespace; no `@`; no aliases/emails/display names/free text.
Validation failure ⇒ FAIL-STOP. Accepted UUID version v4 pinned from repository evidence (`crypto.randomUUID`);
confirming the Supabase auth-subject UUID version against `auth.users` is a **before-live-execution** check
(fail-closed to FAIL-STOP on any non-v4). Test fixtures use a documented **synthetic** UUID
(`2e6f8777-94c8-420e-aa20-c0c481d7ce5a`).

## 9. Mandatory conformance twins

T-a (independent digest vectors, incl. NFC vector and B-1 edge-excludes-authority proof), T-b (negative
remaining / reflected>original / conservation imbalance), T-c (equal cross-system canonical value collapses to
one group), T-d (full-reflection retained ⇒ FAIL-STOP), T-e (duplicate evidence root ⇒ FAIL-STOP), T-f
(cross-transaction edge ⇒ FAIL-STOP), T-g (zero evidence roots ⇒ FAIL-STOP), T-h (allocated<1 ⇒ FAIL-STOP);
mutation twins M1/M6/M7/M8/M9/M10/M11/M19/M23; H-1/H-2/H-3 twins; routing-precedence composed tests; casefold
conformance + runtime-independence; DST / boundary / missing-B5 / full-horizon / insufficient-coverage /
endpoint-validation. Each asserts an exact reason code and fails when its target guard is removed.

---

*End of FROZEN rev-6.1. Implementation changes require a new specification revision.*
