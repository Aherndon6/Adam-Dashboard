# Phase 5G-1D — Companion Amendment 2 (commitment-identity narrowing)

**Status:** DRAFT — PREPARED, NOT IMPLEMENTED. No code, SQL, schema, RPC, RLS, migration,
grant change, or production action is authorized by this document.
**Date:** 2026-07-11
**Author:** Claude (session under Adam)
**Type:** Amendment-by-companion-document. It **does not edit or rewrite** the cleared first
amendment (`docs/phase-5g-1d-amendment-2026-07-11.md`, committed `0c10784`); it **narrows one
paragraph of it by companion**, and controls for implementation where stricter.

## Scope

This companion amendment records a single narrowing, approved by Adam on 2026-07-11 during
Slice-2 red-team review (ChatGPT + own analysis), to the **commitment-identity paragraph of
§B.1** of the first amendment.

## What is narrowed

The first amendment §B.1 (commitment identity) granted **automatic idempotent success** to a
fully-closed-week retry whose **non-empty** commitment operation arrays *project to an
identical intended final state*. **That non-empty automatic-identity guarantee is NARROWED and
no longer available.** Reconstructing the intended final commitment state would require
duplicating the deployed reconciliation RPC's material mutation semantics (`original_amount_cents`
preservation, defaults, normalization, status/`cleared_date`/`resolution_type` transitions),
which violates the no-reimplementation guardrail (plan §5.2).

## The narrowed rule (authoritative for implementation)

1. **Automatic idempotent retry is EMPTY-COMMITMENT-ARRAYS ONLY.** A fully-closed week returns
   automatic idempotent success **only** when `p_new_commitments` is an empty JSON array **and**
   `p_patched` is an empty JSON array.
2. In that empty-array case the wrapper still compares **reconciliation state** and the
   **eligible-nine snapshot state** in-transaction; if both are identical it returns
   **idempotent success without calling either inner RPC and without changing any audit field**.
3. **Non-empty ambiguous outcomes require supervised adjudication.** If either commitment array
   is non-empty on a fully-closed week, the wrapper **does not reproduce or project** the
   reconciliation RPC's commitment mutation semantics, **does not blindly re-call** the
   reconciliation RPC, and routes to **supervised adjudication after a client re-read** via a
   dedicated, machine-distinguishable signal (`ERRCODE='GFA01'`,
   `HINT='REQUIRES_SUPERVISED_ADJUDICATION'`).
4. **Atomicity remains intact.** The limitation affects **automatic outcome adjudication only**,
   **not** transactional persistence: the single-transaction all-or-nothing guarantee is
   unchanged, and the adjudication signal is raised **before any inner call**, so nothing is
   written and **no inner RPC is replayed automatically**.

**Clarification (2026-07-11): applies to BOTH closeout modes.** The empty-array
automatic-identity rule (idempotent success, no inner call) and the non-empty
supervised-adjudication rule (`GFA01`) above apply to ambiguous commit-then-lost-response
retries of **both `normal_closeout` and `approved_reopen`**. A `approved_reopen` whose persisted
reconciliation already equals the submitted result is subject to the identical rule: empty
commitment arrays → idempotent reopen success (no inner call, `recorded_at` preserved);
non-empty → `GFA01`. A genuine reopen (persisted reconciliation differs) applies once and is not
an ambiguous retry.

## What is unchanged

Every other clause of the first amendment stands: reconciliation identity, snapshot identity,
the ordered branch table (§B.2), half-close repair (§C), reopen preservation (§D), wrapper
mechanics (§E), client state machine (§F), the Gate C write-surface register (§G), and
activation timing (§H). Reconciliation-state and snapshot-state identity comparison for the
empty-array case is retained. This companion narrows **only** the non-empty commitment
automatic-identity guarantee.

## Non-authorization

Authorizes no implementation. Does not author Slice-2 SQL, change any grant, run any SQL,
deploy, or activate anything. The cleared first amendment file is unchanged. No household
financial values are recorded here.
