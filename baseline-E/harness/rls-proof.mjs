// baseline-E/harness/rls-proof.mjs
// Design ref: spec §1b — independent RLS visibility-proof harness + evidence contract.
// The INDEPENDENT authoritative row-inventory channel (proven NOT to share the adapter's RLS restriction)
// and its live result are an AUTHORIZED-CAPTURE-time / freeze-readiness step: NOT run here.

export const LIVE_RLS_EVIDENCE = 'PENDING_AUTHORIZED_CAPTURE';

// The evidence the live proof must capture (design §1b). The independence requirement is the crux:
// a naïve reconciliation whose "authoritative" side runs under the SAME role as the adapter is blind to the
// same rows and proves nothing.
export const RLS_EVIDENCE_CONTRACT = Object.freeze({
  required_fields: [
    'extraction_identity',
    'authenticated_role',
    'owner_authorization_status',            // keyed to an immutable subject/user id or role — never a hard-coded email
    'authoritative_row_inventory_channel',   // must be proven independent of the adapter's RLS restriction
    'authoritative_row_count',
    'adapter_visible_row_count',
    'per_row_ids',
    'per_row_content_digests',
    'captured_at_freeze',
    'captured_at_execution',
  ],
  independence_requirement:
    'authoritative channel MUST be proven not to share the adapter RLS restriction (mandatory Mode-2 + freeze-readiness item)',
  fail_stop_on: ['count_mismatch', 'id_mismatch', 'digest_mismatch', 'unexplained_hidden_row', 'independence_not_established'],
});

// Pure four-way reconciliation of a captured evidence pair. Any mismatch ⇒ FAIL-STOP (before freeze).
export function reconcileVisibility({ authoritative, adapterVisible, independenceEstablished = false }) {
  if (!independenceEstablished) return { ok: false, verdict: 'FAIL-STOP', reason: 'independent visibility not established' };
  const digest = (rows) => new Map(rows.map((r) => [r.id, r.content_digest]));
  const A = digest(authoritative), V = digest(adapterVisible);
  if (A.size !== V.size) return { ok: false, verdict: 'FAIL-STOP', reason: `count mismatch ${A.size} vs ${V.size}` };
  for (const [id, d] of A) {
    if (!V.has(id)) return { ok: false, verdict: 'FAIL-STOP', reason: `hidden row: authoritative id ${id} not adapter-visible` };
    if (V.get(id) !== d) return { ok: false, verdict: 'FAIL-STOP', reason: `digest mismatch for id ${id}` };
  }
  for (const id of V.keys()) if (!A.has(id)) return { ok: false, verdict: 'FAIL-STOP', reason: `adapter-visible id ${id} absent from authoritative inventory` };
  return { ok: true, verdict: 'RLS_VISIBILITY_OK' };
}
