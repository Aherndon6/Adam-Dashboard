# Phase 5G-1D — Companion Amendment 3 (genuine-reopen recorded_at re-stamp)

**Status:** CLEARED AND COMMITTED — NOT IMPLEMENTED. No code, SQL, schema, RPC, RLS, migration,
grant change, deployment, activation, or production action is authorized by this document.
**Date:** 2026-07-11
**Author:** Claude (session under Adam)
**Type:** Amendment-by-companion-document. It **does not edit or rewrite** the cleared first
amendment (`0c10784`) or Companion Amendment 2; it **narrows one requirement by companion** and
controls for implementation where stricter/corrective.

## Trigger (grounding finding, accepted 2026-07-11)

While grounding Slice-2 SQL authoring, the deployed `public.save_reconciliation_with_commitments`
RPC was found to **ignore its `p_recorded_at` argument and hardcode `recorded_at = NOW()`** on
both the INSERT and the `ON CONFLICT … UPDATE` (`docs/phase-5f-1-migration.sql` L520–521, L537,
L544, L552). The parameter is **required non-null** but is a **compatibility/signal flag whose
supplied value is discarded**; `recorded_at` is server-owned and always `NOW()` when the RPC runs.

Therefore the earlier requirement (the first amendment and the superseded Slice-2 decision 2) that a **genuine
approved reopen preserve the original `recorded_at`** by passing the persisted value to the RPC
is **infeasible** — the deployed RPC ignores the value, and the wrapper may neither modify the
deployed RPC nor write `weekly_reconciliations` directly nor reproduce its logic.

## The narrowed rule (authoritative for implementation)

1. **The deployed reconciliation RPC is authoritative for actual behavior** and is server-owned;
   it always stamps `recorded_at = NOW()`.
2. **Paths that do NOT call the reconciliation RPC preserve `recorded_at` unchanged:**
   normal-closeout **identity retry**, **half-close repair**, **approved-reopen identity retry
   with empty commitment arrays**, and **GFA01 pre-call adjudication** (raised before any inner
   call). These do not call the RPC, so the stored timestamp is untouched.
3. **A genuine approved reopen re-stamps `recorded_at = NOW()`.** The wrapper calls the deployed
   RPC exactly once; the RPC necessarily overwrites `recorded_at` with `NOW()`. **It is NOT
   claimed that passing the persisted timestamp preserves it** — the argument value is ignored.
4. **The original `recorded_at` is retained in the mandatory supervised before/after reopen
   evidence**, captured **before** execution. The post-reopen `recorded_at` represents the
   **latest successful reconciliation write**, not the original closeout time. Durable historical
   event logging is deferred to 5J.
5. The wrapper's SQL call may pass **any non-null server-controlled compatibility value** to
   satisfy the deployed signature (**prefer `now()` for clarity**), while documenting that the
   **inner RPC owns the stored value and independently writes `NOW()`**.
6. **The public wrapper still does not accept a `p_recorded_at` parameter** (removed since Rev 4);
   no client may supply or backdate an audit timestamp.

## Non-authorization

This change **does not authorize** modifying the deployed RPC, direct table writes, SQL
execution, grant changes, deployment, or activation. The cleared first amendment and Companion
Amendment 2 are unchanged. No household financial values are recorded here.
