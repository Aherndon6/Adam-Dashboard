// baseline-E/live-preflight/live-preflight-evidence-builder.mjs
//
// AUTHORITATIVE transfer-attribution mapping — the committed PRODUCER of the register_transaction_evidence transfer
// fields from a production `transactions` row. This closes the previously-missing derivation: production `transactions`
// has ONLY `transfer_pair_id` (uuid, nullable) — it has NO `is_transfer_leg` and NO `transfer_group_id` column — while
// the preflight controls (P-8, S-7 matched_internal_transfer, XC) consume a DISCRETE `is_transfer_leg` boolean and a
// group id `transfer_group_id ?? transfer_pair_id`. This module derives those fields; it does NOT add any production
// column.
//
// Ratified rules (owner 2026-08-02):
//   is_transfer_leg   = (transfer_pair_id IS NOT NULL)
//   transfer_group_id = transfer_pair_id            // shared-group-id semantic; NOT a mutual pointer
//
// Constraints:
//   - No inference from amount / date / payee / category / memo / mirror-row proximity. The ONLY input is transfer_pair_id.
//   - No normalization / reinterpretation of the identifier (returned verbatim).
//   - Both rows carrying the same transfer_pair_id therefore emit the SAME transfer_group_id (one group).
//   - A debit row whose transfer_pair_id equals its own UUID is valid (shared-group-id self-reference); no pointer
//     chasing / cycle handling is applied — the value is treated purely as an opaque group identifier.
//   - Because the committed clearing digest (`recomputeClearingDigest`) hashes the WHOLE mapped evidence row, adding
//     transfer attribution changes the row's digest — so an internal-transfer record's cleared_transaction_digest MUST
//     be computed from a POST-backfill mapped row, never a pre-backfill one.

// Derive {is_transfer_leg, transfer_group_id} from a single row's production transfer_pair_id.
export function deriveTransferAttribution(transferPairId) {
  const present = transferPairId !== null && transferPairId !== undefined;
  return { is_transfer_leg: present, transfer_group_id: present ? transferPairId : null };
}

// Apply the transfer attribution onto a register_transaction_evidence row the builder has already populated with
// identity / amount / account / cleared / date. Returns a NEW row (no mutation of the input). `transfer_pair_id` is
// PRESERVED verbatim; `transfer_group_id` is emitted only when a pair id is present, and OMITTED otherwise so a
// non-transfer row is byte-identical to the committed non-transfer evidence shape (which carries transfer_pair_id:null
// and no transfer_group_id key).
export function applyTransferAttribution(baseRow, transferPairId) {
  const { is_transfer_leg, transfer_group_id } = deriveTransferAttribution(transferPairId);
  const row = { ...baseRow, is_transfer_leg, transfer_pair_id: transferPairId ?? null };
  if (transfer_group_id !== null) row.transfer_group_id = transfer_group_id;
  else delete row.transfer_group_id;
  return row;
}

// ── AUTHORITATIVE register_transaction_evidence ADAPTER (single source of truth) ──────────────────────────────────
// This is the committed executable transform from immutable-extraction `transactions` rows into the clean
// register_transaction_evidence shape the preflight consumes. Every package builder (including the owner-run external
// bundle) MUST consume THIS output for the register section — no builder may re-implement the transfer attribution, so
// there is exactly one authoritative mapping. is_transfer_leg / transfer_group_id come ONLY from applyTransferAttribution.

// Integer cents from a dollar value; null (fail-closed, no fabrication) if missing / non-finite / fractional-cent.
export function dollarsToCents(v) {
  if (typeof v !== 'number' || !Number.isFinite(v)) return null;
  const c = Math.round(v * 100);
  return Math.abs(v * 100 - c) <= 1e-6 ? c : null;
}

// Emit the clean register_transaction_evidence rows for the extraction's `transactions` rows. Amount is taken from
// `amount_cents` when already integer cents, else converted from the dollar `amount`. No field is inferred from
// payee/category/memo. Returns { rows, gaps } — a null amount is a gap the preflight decides (never fabricated).
export function buildRegisterTransactionEvidence(rawTxns, opts = {}) {
  const rows = [], gaps = [];
  for (const t of (rawTxns || [])) {
    const cents = (typeof t.amount_cents === 'number') ? t.amount_cents : dollarsToCents(t.amount);
    const txn_id = t.txn_id ?? t.id ?? t.transaction_id;
    const base = {
      txn_id,
      account_key: t.account_key ?? t.account ?? null,
      amount_cents: cents,
      cleared: t.cleared,
      represented_as_deduction: t.represented_as_deduction ?? false,
      transaction_date: t.transaction_date ?? t.date ?? null,
      as_of_utc: t.as_of_utc ?? opts.as_of_utc ?? null,
    };
    rows.push(applyTransferAttribution(base, t.transfer_pair_id ?? null));
    if (cents === null) gaps.push({ txn_id, gap: 'amount_cents_missing_or_fractional' });
  }
  return { rows, gaps };
}

// Provenance + FAIL-CLOSED reconciliation for the transfer attribution step of a build. `ctx` carries the immutable
// anchors the caller records (source extraction digest, repo commit of the mapping module, external builder path/digest,
// mapping-spec version). reconciliation_ok=false whenever the emitted rows disagree with the raw transfer_pair_id facts.
export function transferAttributionProvenance(rawTxns, rows, ctx = {}) {
  const byId = new Map(rows.map((r) => [r.txn_id, r]));
  const rawWithPair = (rawTxns || []).filter((t) => (t.transfer_pair_id ?? null) !== null);
  const emittedLegs = rows.filter((r) => r.is_transfer_leg === true);
  const errors = [];
  for (const t of (rawTxns || [])) {
    const pid = t.transfer_pair_id ?? null, id = t.txn_id ?? t.id ?? t.transaction_id, row = byId.get(id);
    if (pid !== null) {
      if (!row || row.is_transfer_leg !== true) errors.push(`RAW_PAIR_WITHOUT_EMITTED_LEG:${id}`);
      if (!row || row.transfer_group_id !== pid) errors.push(`EMITTED_GROUP_ID_NEQ_PAIR_ID:${id}`);
    } else if (row && row.is_transfer_leg === true) errors.push(`SPURIOUS_EMITTED_LEG:${id}`);
  }
  if (rawWithPair.length !== emittedLegs.length) errors.push(`ATTRIBUTION_COUNT_DISAGREE:${rawWithPair.length}!=${emittedLegs.length}`);
  const KNOWN_SPEC = 'legacy-clearing-v2';
  if (ctx.mapping_spec_version != null && ctx.mapping_spec_version !== KNOWN_SPEC) errors.push(`UNRECOGNIZED_MAPPING_VERSION:${ctx.mapping_spec_version}`);
  const groups = {};
  for (const r of emittedLegs) (groups[r.transfer_group_id] ||= []).push(r.txn_id);
  return {
    mapping_module_path: 'baseline-E/live-preflight/live-preflight-evidence-builder.mjs',
    mapping_rule: 'is_transfer_leg=(transfer_pair_id!=null); transfer_group_id=transfer_pair_id (shared-group-id; no inference)',
    mapping_spec_version: ctx.mapping_spec_version ?? KNOWN_SPEC,
    repo_commit: ctx.repo_commit ?? null,
    source_extraction_digest: ctx.source_extraction_digest ?? null,
    builder_path: ctx.builder_path ?? null,
    builder_digest: ctx.builder_digest ?? null,
    transfer_attribution_applied: true,
    raw_rows_with_transfer_pair_id: rawWithPair.length,
    emitted_is_transfer_leg_true: emittedLegs.length,
    transfer_groups: Object.entries(groups).map(([group_id, txn_ids]) => ({ group_id, txn_ids })).sort((a, b) => a.group_id < b.group_id ? -1 : 1),
    reconciliation_ok: errors.length === 0,
    errors,
  };
}
