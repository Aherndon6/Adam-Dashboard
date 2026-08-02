// baseline-E/live-preflight/live-preflight-controls.mjs
// Fail-closed preflight controls S-1..S-7 + P-1..P-9 + query-provenance (PQ), minimum-anchor (AN), and a
// cross-control consistency layer (XC). Hardened per Fable verdict-3 (2026-07-30): every control fails closed on
// what it does NOT model too. Each control(pkg, mut) -> { id, disposition, reason_code, detail }. `mut` injects
// executable control breaks. All changes are ADDITIVE — no previously adopted control is weakened.
import { SUPPORTED_SCHEMA_VERSIONS, EXPECTED_PRODUCTION_PROJECT_REF, USABLE_BALANCE_BASES, BALANCE_BASIS_PRECEDENCE, ATTEST_OK, digest, parseUtcInstant, ATTESTED_SECTIONS, ATTEST_TO_SECTION, SECTION_TO_RELATION, FRESHNESS_POLICY_AUTHORIZED, EXT_DIGEST_SECTIONS, packageFieldsForDigest, REQUIRED_EVIDENCE_TYPE_BY_RESOLUTION, SUPPORTED_EVIDENCE_SOURCES, AUTHORIZED_OWNER_SUBJECT_ID, PINNED_LEGACY_COMMITMENTS, LEGACY_DISPOSITION_VOCAB, ACCEPTED_LEGACY_RECORD_DIGESTS } from './live-preflight-contract.mjs';

const PASS = (id) => ({ id, disposition: 'PASS', reason_code: null });
const HOLD = (id, reason_code, detail) => ({ id, disposition: 'HOLD', reason_code, detail });
const STOP = (id, reason_code, detail) => ({ id, disposition: 'FAIL_STOP', reason_code, detail });

const COMMIT_STATUS = new Set(['open', 'executed', 'cleared', 'voided', 'bank_pending', 'pending', 'stale', 'reflected']);
const RESOLUTION_TYPES = new Set([null, undefined, 'voided', 'paid_from_other_account', 'cleared', 'reflected']);
const SOURCE_ACCOUNTS = new Set(['truist_checking', 'vio_tax', 'lending_club_ef', 'fidelity', 'amex_savings']);
const AUTH_PATHS = new Set(['cash_commitment', 'baseline_e_adjustment']);
const PLAN_YEAR = 2026;
const arr = (pkg, s) => Array.isArray(pkg[s]) ? pkg[s] : [];
const evalWeek = (pkg) => (pkg.execution_identity || {}).evaluation_model_week;

// ── P-1 environment certification ────────────────────────────────────────────────────────────────────────────
export function P1_environment(pkg, mut) {
  const e = pkg.environment_identity || {};
  if (!new Set(['production', 'staging', 'synthetic']).has(e.environment)) return STOP('P-1', 'P1_UNKNOWN_ENVIRONMENT', e.environment);
  if (!mut.ignoreEnvMismatch && e.expected_environment != null && e.environment !== e.expected_environment) return STOP('P-1', 'P1_ENV_MISMATCH', `${e.environment}!=${e.expected_environment}`);
  if (e.environment === 'production') {
    if (e.operator_project_confirmation !== true) return HOLD('P-1', 'P1_NO_OPERATOR_CONFIRMATION');
    if (!mut.ignoreEnvMismatch && e.project_ref !== EXPECTED_PRODUCTION_PROJECT_REF) return STOP('P-1', 'P1_PROJECT_MISMATCH', e.project_ref);
  }
  return PASS('P-1');
}

// ── P-2 as-of coherence + canonical UTC + freshness policy (all evidence sections + attestations + manifest) ──
const TS_FIELDS = { account_balance_evidence: ['as_of_utc'], weekly_reconciliation_evidence: ['recorded_at'], cash_commitment_evidence: ['as_of_utc'], off_model_obligation_evidence: ['as_of_utc'], register_transaction_evidence: ['as_of_utc'], pending_or_uncleared_evidence: ['as_of_utc'], terminal_resolution_evidence: ['as_of_utc'], source_query_manifest: ['extraction_ts'] };
export function P2_asOf(pkg, mut) {
  if (mut.ignoreAsOf) return PASS('P-2');
  const w = (pkg.execution_identity || {}).extraction_window;
  const start = parseUtcInstant(w && w.start), end = parseUtcInstant(w && w.end);
  if (start == null || end == null || start > end) return HOLD('P-2', 'P2_MISSING_OR_BAD_WINDOW');
  for (const [s, fields] of Object.entries(TS_FIELDS)) for (const r of arr(pkg, s)) for (const f of fields) {
    if (r[f] == null) return HOLD('P-2', 'P2_MISSING_TIMESTAMP', `${s}.${f}`);
    const t = parseUtcInstant(r[f]);
    if (t == null) return HOLD('P-2', 'P2_INVALID_OR_NON_UTC_TIMESTAMP', `${s}.${f}=${r[f]}`);
    if (t < start || t > end) return HOLD('P-2', 'P2_INCOHERENT_AS_OF', `${s}.${f}=${r[f]}`);
    if (r.freshness_dependent === true && !FRESHNESS_POLICY_AUTHORIZED) return HOLD('P-2', 'P2_FRESHNESS_POLICY_NOT_AUTHORIZED', s);
  }
  // attestations timestamps too
  for (const [rel, a] of Object.entries(pkg.completeness_attestations || {})) { if (a && a.extraction_ts != null) { const t = parseUtcInstant(a.extraction_ts); if (t == null) return HOLD('P-2', 'P2_INVALID_OR_NON_UTC_TIMESTAMP', `att.${rel}`); if (t < start || t > end) return HOLD('P-2', 'P2_INCOHERENT_AS_OF', `att.${rel}`); } }
  return PASS('P-2');
}

// ── P-3 schema/version ───────────────────────────────────────────────────────────────────────────────────────
export function P3_schema(pkg) { for (const q of arr(pkg, 'source_query_manifest')) if (!SUPPORTED_SCHEMA_VERSIONS.includes(q.schema_version)) return STOP('P-3', 'P3_UNSUPPORTED_SCHEMA', q.schema_version); return PASS('P-3'); }

// ── P-4 evidence integrity ───────────────────────────────────────────────────────────────────────────────────
export function P4_integrity(pkg, mut) {
  if (mut.bypassIntegrity) return PASS('P-4');
  for (const s of ['account_balance_evidence', 'weekly_reconciliation_evidence', 'cash_commitment_evidence', 'off_model_obligation_evidence', 'register_transaction_evidence', 'pending_or_uncleared_evidence', 'terminal_resolution_evidence']) for (const r of arr(pkg, s)) {
    if (typeof r.digest !== 'string') return STOP('P-4', 'P4_MISSING_DIGEST', s);
    const { digest: d, ...content } = r; if (digest(content) !== d) return STOP('P-4', 'P4_EVIDENCE_HASH_MISMATCH', s);
  }
  if (mut.excludeExtDigest) return PASS('P-4'); // MUT: exclude non-evidence sections from hashing
  // NEW-D: whole-section integrity for the non-evidence-array admissibility-relevant sections + package fields
  const ext = (pkg.package_manifest || {}).ext_digests || {};
  const CODE = { baseline_e_adjustments: 'P4_SECTION_DIGEST_MISMATCH', economic_linkages: 'P4_LINKAGE_DIGEST_MISMATCH', completeness_attestations: 'P4_ATTESTATION_DIGEST_MISMATCH', source_query_manifest: 'P4_MANIFEST_DIGEST_MISMATCH' };
  for (const sec of EXT_DIGEST_SECTIONS) { if (ext[sec] == null) return STOP('P-4', 'P4_MISSING_EXT_DIGEST', sec); if (digest(pkg[sec] ?? null) !== ext[sec]) return STOP('P-4', CODE[sec], sec); }
  if (ext.package_fields == null) return STOP('P-4', 'P4_MISSING_EXT_DIGEST', 'package_fields');
  if (digest(packageFieldsForDigest(pkg)) !== ext.package_fields) return STOP('P-4', 'P4_PACKAGE_DIGEST_MISMATCH', 'package_fields');
  return PASS('P-4');
}

// ── P-5 cardinality (manifest section_row_counts vs actual) ──────────────────────────────────────────────────
export function P5_cardinality(pkg, mut) {
  if (mut.ignoreCardinality) return PASS('P-5');
  const counts = (pkg.package_manifest || {}).section_row_counts || {};
  for (const s of Object.keys(TS_FIELDS).concat(['pending_or_uncleared_evidence'])) if (counts[s] !== arr(pkg, s).length) return HOLD('P-5', 'P5_MANIFEST_COUNT_MISMATCH', `${s}:${counts[s]}!=${arr(pkg, s).length}`);
  return PASS('P-5');
}

// ── PQ query provenance (every evidence section tied to a valid manifest entry) ──────────────────────────────
const REQUIRED_Q = ['query_id', 'relation', 'environment', 'schema_version', 'extraction_ts', 'row_count', 'execution_status', 'filter'];
export function PQ_provenance(pkg, mut) {
  if (mut.ignoreProvenance) return PASS('PQ');
  const manifest = arr(pkg, 'source_query_manifest');
  const byId = new Map(); const byRel = new Map();
  for (const q of manifest) {
    for (const f of REQUIRED_Q) if (q[f] == null) return HOLD('PQ', 'PQ_MISSING_PROVENANCE', `${q.query_id ?? '?'}.${f}`);
    if (byId.has(q.query_id)) return STOP('PQ', 'PQ_DUPLICATE_QUERY_ID', q.query_id);
    byId.set(q.query_id, q);
    if (!mut.ignoreDupRelation && byRel.has(q.relation)) { // NEW-A: exactly one authoritative manifest entry per relation (no partition contract supported)
      const prev = byRel.get(q.relation);
      if (prev.row_count !== q.row_count) return STOP('PQ', 'PQ_CONFLICTING_RELATION_COUNT', q.relation);
      if (prev.filter !== q.filter || prev.extraction_ts !== q.extraction_ts) return STOP('PQ', 'PQ_CONFLICTING_RELATION_SCOPE', q.relation);
      if (prev.digest != null && q.digest != null && prev.digest !== q.digest) return STOP('PQ', 'PQ_CONFLICTING_RELATION_DIGEST', q.relation);
      return STOP('PQ', 'PQ_DUPLICATE_RELATION_ENTRY', q.relation);
    }
    byRel.set(q.relation, q);
    if (q.execution_status !== 'success') return HOLD('PQ', 'PQ_EXECUTION_NOT_SUCCESS', `${q.relation}:${q.execution_status}`);
    if (!SUPPORTED_SCHEMA_VERSIONS.includes(q.schema_version)) return STOP('PQ', 'PQ_SCHEMA_MISMATCH', q.schema_version);
    const env = (pkg.environment_identity || {}).environment;
    if (!mut.ignoreEnvMismatch && q.environment !== env) return STOP('PQ', 'PQ_ENV_MISMATCH', `${q.relation}:${q.environment}!=${env}`);
  }
  // every evidence-bearing section must reference a manifest entry (by relation) whose row_count matches
  for (const [sec, rel] of Object.entries(SECTION_TO_RELATION)) {
    const q = manifest.find((x) => x.relation === rel);
    if (!q) return HOLD('PQ', 'PQ_MISSING_QUERY_LINK', sec);
    if (q.row_count !== arr(pkg, sec).length) return HOLD('PQ', 'PQ_ROWCOUNT_MISMATCH', `${rel}:${q.row_count}!=${arr(pkg, sec).length}`);
  }
  // orphan manifest entry: a relation not mapped to any known section
  const known = new Set(Object.values(SECTION_TO_RELATION).concat(['source_query_manifest']));
  for (const q of manifest) if (!known.has(q.relation)) return HOLD('PQ', 'PQ_ORPHAN_MANIFEST', q.relation);
  return PASS('PQ');
}

// ── P-6 stable-identity uniqueness (reconciliation-week uniqueness owned by S-3) ─────────────────────────────
export function P6_uniqueness(pkg) {
  const NS = [['cash_commitment_evidence', 'expected_item_id'], ['register_transaction_evidence', 'txn_id'], ['off_model_obligation_evidence', 'obligation_id'], ['account_balance_evidence', 'account_key'], ['pending_or_uncleared_evidence', 'txn_id']];
  for (const [s, key] of NS) { const seen = new Set(); for (const r of arr(pkg, s)) { const k = r[key]; if (k == null) return STOP('P-6', 'P6_MISSING_IDENTITY', `${s}.${key}`); if (seen.has(k)) return STOP('P-6', 'P6_DUPLICATE_IDENTITY', `${s}.${key}=${k}`); seen.add(k); } }
  return PASS('P-6');
}

// ── P-7 economic identity (authoritative, not free-text) + no double counting ────────────────────────────────
// The linkage namespace vocabulary is CLOSED (RG-1): a linkage SOURCE is a local deduction row; a linkage TARGET is an
// authoritative economic identity only. A target may never be another local deduction row (RG-4). No id token may be a
// linkage source AND a linkage target (RG-3: chains/2-cycles/shared-token indirection, checked namespace-agnostically).
// A direct economic_event_id and a commitment expected_item_id are ONE authoritative id space, so `event:X` and
// `commitment:X` are the SAME event (RG-2). No self-asserted/inferred aggregation exemption (RG-5). Every linkage
// identity is validated (OBS-5) BEFORE namespace construction/dedup: non-empty scalar ids; the source must resolve to
// exactly one deduction record; the target must resolve to an ESTABLISHED authoritative identity (a commitment in the
// package, or an event carried as a direct economic_event_id by some record — NEVER the linkage's own target string);
// and no linkage may be left unconsumed (orphan).
const LINKAGE_SOURCE_NS = new Set(['adjustment', 'pending']);           // local deduction rows that require resolution
const LINKAGE_TARGET_NS = new Set(['event', 'commitment']);            // authoritative economic identities only
const econKey = (nsid) => { const i = nsid.indexOf(':'); const ns = nsid.slice(0, i), id = nsid.slice(i + 1); return (ns === 'event' || ns === 'commitment') ? `econ:${id}` : nsid; };
const isValidId = (v) => typeof v === 'string' && v.trim().length > 0 && !/[\u0000-\u001F\u007F]/.test(v);
const idFault = (v) => (v == null || (typeof v === 'string' && v.trim().length === 0)) ? 'missing' : (typeof v !== 'string' || /[\u0000-\u001F\u007F]/.test(v)) ? 'invalid' : null;
export function P7_economicIdentity(pkg, mut) {
  if (mut.allowDoubleCount) return PASS('P-7');
  const linkages = arr(pkg, 'economic_linkages');
  const commitments = arr(pkg, 'cash_commitment_evidence');
  const adjustments = arr(pkg, 'baseline_e_adjustments');
  const pendings = arr(pkg, 'pending_or_uncleared_evidence');
  // OBS-5 authoritative identity universe. An event is ESTABLISHED only by a record carrying that direct
  // economic_event_id; a commitment by an expected_item_id in the package. Built from valid ids only.
  const commitmentCount = new Map();
  for (const c of commitments) if (isValidId(c.expected_item_id)) commitmentCount.set(c.expected_item_id, (commitmentCount.get(c.expected_item_id) || 0) + 1);
  const eventUniverse = new Set();
  for (const p of pendings) if (isValidId(p.economic_event_id)) eventUniverse.add(p.economic_event_id);
  for (const a of adjustments) if (isValidId(a.economic_event_id)) eventUniverse.add(a.economic_event_id);
  const sourceRecord = new Set();
  for (const p of pendings) if (isValidId(p.txn_id)) sourceRecord.add(`pending:${p.txn_id}`);
  for (const a of adjustments) if (isValidId(a.adjustment_id)) sourceRecord.add(`adjustment:${a.adjustment_id}`);

  const seenLink = new Set(); const targetsBySource = new Map(); const sourceIds = new Set(); const targetIds = new Set();
  for (const l of linkages) {
    for (const f of ['source_namespace', 'target_namespace', 'linkage_type', 'cardinality']) if (l[f] == null) return HOLD('P-7', 'P7_LINKAGE_IDENTITY_UNRESOLVED', f);
    if (!['1:1', 'n:1', '1:n'].includes(l.cardinality)) return HOLD('P-7', 'P7_LINKAGE_CARDINALITY_INVALID', l.cardinality);
    // OBS-5: validate every identity BEFORE namespace construction, comparison, hashing, or graph traversal.
    if (!mut.acceptEmptySourceId) { const f = idFault(l.source_id); if (f === 'missing') return HOLD('P-7', 'P7_LINKAGE_SOURCE_ID_MISSING', String(l.source_id)); if (f === 'invalid') return HOLD('P-7', 'P7_LINKAGE_SOURCE_ID_INVALID', typeof l.source_id); }
    if (!mut.acceptEmptyTargetId) { const f = idFault(l.target_id); if (f === 'missing') return HOLD('P-7', 'P7_LINKAGE_TARGET_ID_MISSING', String(l.target_id)); if (f === 'invalid') return HOLD('P-7', 'P7_LINKAGE_TARGET_ID_INVALID', typeof l.target_id); }
    // RG-1 / RG-4: closed namespace vocabulary — source is a local deduction row; target is an authoritative identity.
    if (!mut.ignoreNamespaceVocab && !LINKAGE_SOURCE_NS.has(l.source_namespace)) return HOLD('P-7', 'P7_LINKAGE_SOURCE_NAMESPACE_UNKNOWN', l.source_namespace);
    if (!mut.ignoreNamespaceVocab && !LINKAGE_TARGET_NS.has(l.target_namespace)) return HOLD('P-7', 'P7_LINKAGE_TARGET_NOT_AUTHORITATIVE', l.target_namespace);
    const skey = `${l.source_namespace}:${l.source_id}`, tkey = `${l.target_namespace}:${l.target_id}`;
    if (skey === tkey) return HOLD('P-7', 'P7_LINKAGE_TARGET_CONFLICT', skey);         // trivial self-cycle
    const rec = `${skey}=>${tkey}`;
    if (seenLink.has(rec)) return HOLD('P-7', 'P7_DUPLICATE_LINKAGE', rec); seenLink.add(rec);
    const set = targetsBySource.get(skey) || new Set(); set.add(tkey); targetsBySource.set(skey, set);
    sourceIds.add(l.source_id); targetIds.add(l.target_id);
  }
  // RG-3 (namespace-agnostic, independent of vocab): no id token may be BOTH a linkage source and a linkage target
  // (chains A->B->C, 2-cycles, shared-token indirection). Fires even when every namespace is individually valid.
  if (!mut.allowGraphIndirection) for (const id of targetIds) if (sourceIds.has(id)) return HOLD('P-7', 'P7_LINKAGE_GRAPH_INDIRECTION', id);
  // ambiguity: one source may not declare multiple distinct targets (structural, before existence).
  const linkBySource = new Map();
  for (const [skey, set] of targetsBySource) { if (set.size > 1 && !mut.ignoreLinkageAmbiguity) return HOLD('P-7', 'P7_LINKAGE_TARGET_AMBIGUOUS', skey); linkBySource.set(skey, [...set][0]); }
  // OBS-5 source + authoritative-target existence.
  for (const l of linkages) {
    if (!mut.ignoreSourceExistence && !sourceRecord.has(`${l.source_namespace}:${l.source_id}`)) return HOLD('P-7', 'P7_LINKAGE_SOURCE_NOT_FOUND', `${l.source_namespace}:${l.source_id}`);
    if (l.target_namespace === 'commitment' && !mut.ignoreCommitmentTargetExistence) {
      const n = commitmentCount.get(l.target_id) || 0;
      if (n === 0) return HOLD('P-7', 'P7_LINKAGE_COMMITMENT_NOT_FOUND', l.target_id);
      if (n > 1) return HOLD('P-7', 'P7_LINKAGE_TARGET_AMBIGUOUS', l.target_id);
    } else if (l.target_namespace === 'event' && !mut.trustEventTargetEstablished) {
      if (!eventUniverse.has(l.target_id)) return HOLD('P-7', 'P7_LINKAGE_EVENT_NOT_ESTABLISHED', l.target_id); // linkage's own string is NOT proof
    }
  }

  const resolve = (ns, rowId, directEvent) => {
    const skey = `${ns}:${rowId}`;
    if (isValidId(directEvent)) return { id: `event:${directEvent}`, authoritative: true, skey };
    if (linkBySource.has(skey)) { const t = linkBySource.get(skey); return { id: t, authoritative: true, skey }; }
    return { id: null, authoritative: false, skey };
  };
  const deductions = []; const consumed = new Set();
  for (const c of commitments) { if (!isValidId(c.expected_item_id)) return HOLD('P-7', 'P7_LINKAGE_AUTHORITATIVE_TARGET_REQUIRED', 'commitment'); deductions.push({ id: `commitment:${c.expected_item_id}`, authoritative: true, path: 'commitment' }); }
  for (const adj of adjustments) { const d = resolve('adjustment', adj.adjustment_id, adj.economic_event_id); deductions.push({ ...d, path: 'adjustment' }); consumed.add(d.skey); }
  for (const p of pendings) if (p.represented_as_deduction) { const d = resolve('pending', p.txn_id, p.economic_event_id); deductions.push({ ...d, path: 'pending' }); consumed.add(d.skey); }
  // OBS-5 orphan: every linkage must be consumed by a real deduction (its source resolves through it). Never silently ignored.
  if (!mut.allowOrphanLinkage) for (const l of linkages) { const skey = `${l.source_namespace}:${l.source_id}`; if (!consumed.has(skey)) return HOLD('P-7', 'P7_ORPHAN_LINKAGE', skey); }

  const seen = new Map();
  for (const d of deductions) {
    if (!d.authoritative || d.id == null) return HOLD('P-7', 'P7_LINKAGE_AUTHORITATIVE_IDENTITY_REQUIRED', d.path);
    if (mut.dedupLocalRowFallback) continue; // MUT: fall back to the (unique) local row id -> never collides
    // RG-2: a direct economic_event_id equal to a commitment expected_item_id is the SAME economic event.
    const key = mut.ignoreEventCommitmentEquivalence ? d.id : econKey(d.id);
    if (seen.has(key)) return STOP('P-7', seen.get(key) === d.path ? 'P7_LINKAGE_WITHIN_PATH_DOUBLE_COUNT' : 'P7_DUPLICATE_LINKED_ECONOMIC_EVENT', key);
    seen.set(key, d.path);
  }
  return PASS('P-7');
}

// ── P-8 transfer treatment (strict: exactly two well-formed mirror legs; no near-net; explicit group identity) ─
export function P8_transfer(pkg, mut) {
  if (mut.allowTransferDouble) return PASS('P-8');
  const legs = arr(pkg, 'register_transaction_evidence').filter((t) => t.is_transfer_leg);
  const groupIdOf = (l) => l.transfer_group_id ?? l.transfer_pair_id;
  const byGroup = new Map();
  for (const l of legs) { const g = groupIdOf(l); if (g == null) return HOLD('P-8', 'P8_MISSING_TRANSFER_IDENTITY', l.txn_id); (byGroup.get(g) || byGroup.set(g, []).get(g)).push(l); }
  // a transfer group id must not appear on any non-transfer record (mixed group)
  for (const t of arr(pkg, 'register_transaction_evidence')) if (!t.is_transfer_leg && (t.transfer_group_id != null || t.transfer_pair_id != null) && byGroup.has(groupIdOf(t))) return HOLD('P-8', 'P8_MIXED_TRANSFER_GROUP', t.txn_id);
  for (const [g, ls] of byGroup) {
    if (ls.length !== 2) return HOLD('P-8', 'P8_MALFORMED_LEG_COUNT', `${g}:${ls.length}`);
    const [a, b] = ls;
    if (a.txn_id === b.txn_id) return HOLD('P-8', 'P8_DUPLICATE_LEG_IDENTITY', g);
    if (Math.sign(a.amount_cents) === Math.sign(b.amount_cents)) return HOLD('P-8', 'P8_SAME_DIRECTION', g);
    if (Math.abs(a.amount_cents) !== Math.abs(b.amount_cents)) return HOLD('P-8', 'P8_UNEQUAL_AMOUNTS', g); // no near-net tolerance
    if (a.account_key == null || b.account_key == null) return HOLD('P-8', 'P8_INCOMPATIBLE_ACCOUNTS', g);
    if (a.represented_as_deduction || b.represented_as_deduction) return STOP('P-8', 'P8_TRANSFER_DOUBLE_COUNT', g);
  }
  return PASS('P-8');
}

// ── P-9 authoritative balance selection ──────────────────────────────────────────────────────────────────────
export function P9_balance(pkg) {
  const byAcct = new Map();
  for (const b of arr(pkg, 'account_balance_evidence')) { const g = byAcct.get(b.account_key) || byAcct.set(b.account_key, []).get(b.account_key); g.push(b); }
  for (const [acct, rows] of byAcct) {
    const selected = rows.find((r) => r.selected === true) || (rows.length === 1 ? rows[0] : null);
    if (!selected) return HOLD('P-9', 'P9_AMBIGUOUS_BALANCE', acct);
    if (!USABLE_BALANCE_BASES.includes(selected.balance_basis)) return HOLD('P-9', 'P9_NON_AUTHORITATIVE_BALANCE', `${acct}:${selected.balance_basis}`);
    if (typeof selected.balance_cents !== 'number' || !Number.isFinite(selected.balance_cents)) return HOLD('P-9', 'P9_MISSING_BALANCE', acct);
    const best = rows.map((r) => r.balance_basis).filter((x) => BALANCE_BASIS_PRECEDENCE.includes(x)).sort((x, y) => BALANCE_BASIS_PRECEDENCE.indexOf(y) - BALANCE_BASIS_PRECEDENCE.indexOf(x))[0];
    if (best && best !== selected.balance_basis) return HOLD('P-9', 'P9_LOWER_PRECEDENCE_SELECTED', `${acct}:${selected.balance_basis}<${best}`);
  }
  return PASS('P-9');
}

// ── AN minimum authoritative checking anchor ─────────────────────────────────────────────────────────────────
export function AN_anchor(pkg, mut) {
  if (mut && mut.ignoreAnchor) return PASS('AN');
  const balAnchors = arr(pkg, 'account_balance_evidence').filter((b) => b.account_key === 'truist_checking' && USABLE_BALANCE_BASES.includes(b.balance_basis) && Number.isFinite(b.balance_cents));
  const reconAnchors = arr(pkg, 'weekly_reconciliation_evidence').filter((r) => Number.isFinite(r.chk_cents) && USABLE_BALANCE_BASES.includes(r.balance_basis));
  if (balAnchors.length + reconAnchors.length === 0) return HOLD('AN', 'ANCHOR_MISSING_AUTHORITATIVE_CHECKING');
  // competing unresolved checking balances (>1 with none selected)
  const chk = arr(pkg, 'account_balance_evidence').filter((b) => b.account_key === 'truist_checking');
  if (chk.length > 1 && !chk.some((b) => b.selected === true)) return HOLD('AN', 'ANCHOR_AMBIGUOUS_COMPETING');
  return PASS('AN');
}

// ── S-1 material off-model referential integrity ─────────────────────────────────────────────────────────────
// RG-6: the recognized section-G obligation schema. A field outside this set (with no authoritative path) is a
// self-asserted authority signal and fails closed with a dedicated code — it never grants an exemption.
const KNOWN_OBLIGATION_FIELDS = new Set(['obligation_id', 'label', 'description', 'material', 'amount_cents', 'source_account', 'authoritative_path', 'linked_economic_id', 'as_of_utc', 'digest', 'affects_deployable_cash', 'completed', 'freshness_dependent', 'model_year', 'origin_model_week']);
// NEW-C: a referenced commitment is a LIVE deduction only when it still reserves (mirrors state-parity isReservedAsOf).
function isReservingCommitment(c, evw) {
  return c.model_year === PLAN_YEAR && Number.isInteger(c.origin_model_week) && c.origin_model_week <= evw && !!c.affects_deployable_cash
    && c.status !== 'voided' && c.resolution_type !== 'voided' && c.resolution_type !== 'paid_from_other_account'
    && !(c.reflected_model_week != null && c.reflected_model_week <= evw) && (c.resolved_model_week == null || c.resolved_model_week > evw)
    && typeof c.amount_cents === 'number' && c.amount_cents > 0;
}
export function S1_offModel(pkg, mut) {
  if (mut.offModelWarningOnly) return PASS('S-1');
  const commits = arr(pkg, 'cash_commitment_evidence');
  const adjustments = arr(pkg, 'baseline_e_adjustments');
  const evw = evalWeek(pkg);
  const dedUse = new Map();
  for (const g of arr(pkg, 'off_model_obligation_evidence')) {
    // Owner ruling (2026-07-30): NO self-asserted section-G exemption is authoritative. A package-builder
    // affects_deployable_cash:false, a self-asserted material:false, and a completed:true flag are NOT proof of
    // non-cash-impact — every section-G obligation must resolve to a live authoritative deduction, else HOLD.
    // (Mutations simulate a validator that wrongly trusts each self-assertion.)
    if (mut.trustAffectsFalse && g.affects_deployable_cash === false) continue;
    if (mut.trustMaterialFalse && g.material === false) continue;
    if (mut.trustCompleted && g.completed === true) continue;
    if (!AUTH_PATHS.has(g.authoritative_path)) {
      // RG-6: a section-G obligation carrying a field outside the known schema is a self-asserted authority signal, not
      // an authoritative deduction — name it distinctly (still fail-closed; no unknown field ever grants an exemption).
      const unknownField = Object.keys(g).find((k) => !KNOWN_OBLIGATION_FIELDS.has(k));
      const code = g.affects_deployable_cash === false ? 'S1_UNSUPPORTED_CASH_IMPACT_CLASSIFICATION'
        : g.material === false ? 'S1_SELF_ASSERTED_IMMATERIALITY'
        : g.completed === true ? 'S1_OFF_MODEL_DEDUCTION_REQUIRED'
        : unknownField ? 'S1_UNSUPPORTED_AUTHORITY_FIELD'
        : g.material === undefined ? 'S1_MATERIALITY_UNRESOLVED' : 'S1_OFF_MODEL_DEDUCTION_MISSING';
      return HOLD('S-1', code, unknownField ? `${g.obligation_id}:${unknownField}` : g.obligation_id);
    }
    const isCommit = g.authoritative_path === 'cash_commitment';
    const pool = isCommit ? commits : adjustments; const key = isCommit ? 'expected_item_id' : 'adjustment_id';
    const matches = pool.filter((x) => x[key] === g.linked_economic_id);
    if (matches.length === 0) return HOLD('S-1', 'S1_DANGLING_REFERENCE', `${g.obligation_id}->${g.linked_economic_id}`);
    if (matches.length > 1) return HOLD('S-1', 'S1_AMBIGUOUS_REFERENCE', g.linked_economic_id);
    const m = matches[0];
    if (m.amount_cents !== g.amount_cents) return HOLD('S-1', 'S1_REFERENCE_AMOUNT_MISMATCH', g.obligation_id);
    if (m.source_account != null && g.source_account != null && m.source_account !== g.source_account) return HOLD('S-1', 'S1_REFERENCE_SOURCE_MISMATCH', g.obligation_id);
    // NEW-C: deduction liveness (aligned with committed state-parity reservation semantics)
    if (!mut.ignoreDeductionLiveness) {
      if (isCommit) {
        if (m.affects_deployable_cash === false) return HOLD('S-1', 'S1_REFERENCED_DEDUCTION_NOT_LIVE', g.obligation_id);
        if (m.reflected_in_actuals === true) return HOLD('S-1', 'S1_REFERENCED_DEDUCTION_ALREADY_REFLECTED', g.obligation_id);
        if (!isReservingCommitment(m, evw)) {
          const code = (m.status === 'voided' || m.resolution_type === 'voided' || m.resolution_type === 'paid_from_other_account') ? 'S1_REFERENCED_COMMITMENT_NOT_RESERVING'
            : (m.resolved_model_week != null && m.resolved_model_week <= evw) ? 'S1_REFERENCED_DEDUCTION_ALREADY_RELEASED'
            : 'S1_REFERENCED_DEDUCTION_NOT_LIVE';
          return HOLD('S-1', code, g.obligation_id);
        }
      } else if (m.active === false || m.affects_deployable_cash === false || m.superseded === true || m.reversed === true || m.consumed === true || m.expired === true) {
        return HOLD('S-1', 'S1_REFERENCED_ADJUSTMENT_INACTIVE', g.obligation_id);
      }
    }
    if (dedUse.has(g.linked_economic_id) && dedUse.get(g.linked_economic_id) !== g.obligation_id) return HOLD('S-1', 'S1_SHARED_DEDUCTION', g.linked_economic_id);
    dedUse.set(g.linked_economic_id, g.obligation_id);
  }
  return PASS('S-1');
}

// ── S-2 null reconciliation ──────────────────────────────────────────────────────────────────────────────────
export function S2_nullRecon(pkg, mut) {
  if (mut.nullReconAccepted) return PASS('S-2');
  for (const r of arr(pkg, 'weekly_reconciliation_evidence')) {
    if (!('chk_cents' in r)) return HOLD('S-2', 'S2_MISSING_CHK', r.week_num);
    if (r.chk_cents === null || typeof r.chk_cents !== 'number' || !Number.isFinite(r.chk_cents)) return HOLD('S-2', 'S2_NULL_CHK', r.week_num);
    if (!USABLE_BALANCE_BASES.includes(r.balance_basis)) return HOLD('S-2', 'S2_UNUSABLE_BASIS', `${r.week_num}:${r.balance_basis}`);
  }
  return PASS('S-2');
}

// ── S-3 duplicate/conflicting reconciliation (uniqueness key = week_num) ─────────────────────────────────────
export function S3_dupRecon(pkg, mut) {
  if (mut.ignoreDupRecon) return PASS('S-3');
  const seen = new Map();
  for (const r of arr(pkg, 'weekly_reconciliation_evidence')) { if (seen.has(r.week_num)) { if (seen.get(r.week_num) !== r.chk_cents) return STOP('S-3', 'S3_CONFLICTING_RECON', r.week_num); return STOP('S-3', 'S3_DUPLICATE_RECON', r.week_num); } seen.set(r.week_num, r.chk_cents); }
  return PASS('S-3');
}

// ── S-4 invalid commitments ──────────────────────────────────────────────────────────────────────────────────
export function S4_commitments(pkg, mut) {
  const clearing = new Set();
  for (const c of arr(pkg, 'cash_commitment_evidence')) {
    if (typeof c.expected_item_id !== 'string' || !c.expected_item_id) return STOP('S-4', 'S4_MISSING_IDENTITY');
    if (!mut.negativeCommitmentAccepted && (typeof c.amount_cents !== 'number' || !Number.isFinite(c.amount_cents) || !Number.isInteger(c.amount_cents))) return STOP('S-4', 'S4_MALFORMED_AMOUNT', c.expected_item_id);
    if (!mut.negativeCommitmentAccepted && c.amount_cents < 0) return STOP('S-4', 'S4_NEGATIVE_AMOUNT', c.expected_item_id);
    if (c.amount_cents === 0 && c.affects_deployable_cash && c.zero_allowed !== true) return HOLD('S-4', 'S4_ZERO_AMOUNT_DISALLOWED', c.expected_item_id);
    if (!COMMIT_STATUS.has(c.status)) return STOP('S-4', 'S4_UNSUPPORTED_STATUS', c.status);
    if (!RESOLUTION_TYPES.has(c.resolution_type)) return STOP('S-4', 'S4_UNSUPPORTED_RESOLUTION', c.resolution_type);
    if (c.resolution_type === 'voided' && c.status != null && c.status !== 'voided') return STOP('S-4', 'S4_CONTRADICTORY_STATE', c.expected_item_id);
    if (!SOURCE_ACCOUNTS.has(c.source_account)) return STOP('S-4', 'S4_INVALID_SOURCE_ACCOUNT', c.source_account);
    if (c.model_year !== PLAN_YEAR) return STOP('S-4', 'S4_INVALID_MODEL_YEAR', c.model_year);
    if (!Number.isInteger(c.origin_model_week) || c.origin_model_week < 1 || c.origin_model_week > 31) return STOP('S-4', 'S4_INVALID_MODEL_WEEK', c.origin_model_week);
    if (c.cleared_transaction_id != null) {
      if (clearing.has(c.cleared_transaction_id)) return STOP('S-4', 'S4_DUPLICATE_CLEARING_LINKAGE', c.cleared_transaction_id);
      clearing.add(c.cleared_transaction_id);
      if (c.cleared_amount_cents != null && c.cleared_amount_cents !== c.amount_cents) return STOP('S-4', 'S4_CLEARING_AMOUNT_MISMATCH', c.expected_item_id);
      if (c.cleared_source_account != null && c.cleared_source_account !== c.source_account) return STOP('S-4', 'S4_CLEARING_SOURCE_MISMATCH', c.expected_item_id);
    }
  }
  return PASS('S-4');
}

// ── S-5 uncleared Register (no unauthorized materiality-threshold escape) ────────────────────────────────────
export function S5_uncleared(pkg, mut) {
  if (mut.unclearedOmitted) return PASS('S-5');
  for (const p of arr(pkg, 'pending_or_uncleared_evidence')) {
    if (p.immaterial_under_authorized_threshold === true) { if (!mut.acceptThreshold) return HOLD('S-5', 'S5_UNAUTHORIZED_THRESHOLD', p.txn_id); else continue; } // no threshold artifact authorized -> HOLD (mutant exempts)
    if (p.reflected_in_authoritative !== true && p.represented_as_deduction !== true) return HOLD('S-5', 'S5_UNCLEARED_UNRECONCILED', p.txn_id);
  }
  return PASS('S-5');
}

// ── S-6 obligation-set completeness (all evidence sections attested; verified_empty strict) ──────────────────
export function S6_completeness(pkg, mut) {
  const att = pkg.completeness_attestations || {};
  for (const rel of ATTESTED_SECTIONS) {
    const a = att[rel];
    if (!a) return HOLD('S-6', 'S6_MISSING_ATTESTATION', rel);
    const sec = ATTEST_TO_SECTION[rel];
    const secLen = arr(pkg, sec).length;
    for (const f of ['status', 'attested', 'rows_visible', 'rows_returned', 'query_id', 'schema_version', 'extraction_ts', 'source_namespace']) if (a[f] === undefined) return HOLD('S-6', 'S6_ATTESTATION_INCOMPLETE', `${rel}.${f}`);
    if (a.rows_returned !== secLen) return HOLD('S-6', 'S6_COUNT_MISMATCH', `${rel}:${a.rows_returned}!=${secLen}`);
    if (mut.failedFetchAsEmpty && a.status === 'failed_fetch') continue;
    if (mut.acceptUnattested && a.status === 'unattested') continue;
    if (!(ATTEST_OK.includes(a.status) && a.attested === true)) {
      const map = { failed_fetch: 'S6_FAILED_FETCH', partial: 'S6_PARTIAL_LOAD', malformed: 'S6_MALFORMED_RESULT', rls_filtered: 'S6_RLS_FILTERED', schema_mismatch: 'S6_SCHEMA_MISMATCH', silent_empty: 'S6_SILENT_EMPTY', unattested: 'S6_UNATTESTED', count_mismatch: 'S6_COUNT_MISMATCH', query_manifest_mismatch: 'S6_QUERY_MANIFEST_MISMATCH' };
      return HOLD('S-6', map[a.status] || 'S6_OBLIGATION_SET_INCOMPLETE', rel);
    }
    if (a.status === 'verified_empty') {
      if (!mut.acceptVerifiedEmptyNoVisible && a.rows_visible !== true) return HOLD('S-6', 'S6_NO_ROWS_VISIBLE', rel);
      if (a.rows_returned !== 0) return HOLD('S-6', 'S6_VERIFIED_EMPTY_NONZERO', rel);
      if (a.zero_rows_verified !== true) return HOLD('S-6', 'S6_ZERO_NOT_VERIFIED', rel);
    }
  }
  return PASS('S-6');
}

// ── S-7 reserve-release evidence (v3.1 s7-rev-8.3-bankcleared) ────────────────────────────────────────────────
// Cross-checks section-F releases against section-J terminal evidence (reproduces committed state-parity SP-79) AND
// adds the durable-clearing lane: a `cleared`/`reflected` commitment is RELEASED and requires durable `bank_cleared`
// evidence (G1 — closes the capacity bypass). Evidence records are routed by `evidence_source`: ABSENT -> the committed
// path (unchanged; every committed fixture takes this path); `au11`/`legacy_adjudication` -> the new lanes; any explicit
// other value -> FAIL-STOP (G2). Phase 0 collects every global FAIL-STOP (source, cleared+voided overlap, legacy
// authority/registry/digest/vocab/pinned-six on ACTIVE records only, supersession structure, cross-lane txn reuse)
// BEFORE any per-commitment HOLD, so no HOLD can mask a FAIL-STOP (G5/G7/G8/G9). All committed reason codes and
// fixtures are preserved: the new logic fires only on evidence_source-tagged records, cleared/reflected commitments, or
// legacy records — none of which appear in the committed fixtures. Pre-freeze the accepted-registry is empty, so every
// legacy_adjudication record fails closed (S7_ADJUDICATION_NOT_IN_REGISTRY) — the correct pre-freeze posture.
// H4: the released predicate is defined ONCE here and reused by XC (XC.actuallyReleased) so the two never diverge.
function releasedPredicate(c, evw, mut) {
  return (c.reflected_model_week != null && evw != null && c.reflected_model_week <= evw)
    || (c.resolved_model_week != null && evw != null && c.resolved_model_week <= evw)
    || c.status === 'voided' || c.resolution_type === 'voided' || c.resolution_type === 'paid_from_other_account'
    || (!(mut && mut.ignoreClearedRelease) && (c.resolution_type === 'cleared' || c.resolution_type === 'reflected')); // G1 additive (MUT reverts)
}
const V4_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const isValidSubjectId = (v) => typeof v === 'string' && V4_UUID_RE.test(v);
// Family-B record_digest preimage = canonical-JSON of the record minus its own record_digest and the P-4 per-record digest.
const recomputeRecordDigest = (j) => { const { record_digest, digest: _perRecord, ...rest } = j; return digest(rest); };
// F-1: authoritative clearing digest recomputed from a referenced Register row (excluding its P-4 per-record digest).
const recomputeClearingDigest = (tx) => { const { digest: _perRecord, ...rest } = tx; return digest(rest); };

export function S7_reserveRelease(pkg, mut) {
  const evw = evalWeek(pkg);
  const js = arr(pkg, 'terminal_resolution_evidence');
  const commits = arr(pkg, 'cash_commitment_evidence');
  const registerRows = arr(pkg, 'register_transaction_evidence');
  const commitIds = new Set(commits.map((c) => c.expected_item_id));

  // ── PHASE 0 — global FAIL-STOP scans (evaluated before any per-commitment HOLD) ──
  // G2: evidence_source is a closed set. Absent -> committed path. Any explicit value outside the set (incl null) STOPs.
  if (!mut.ignoreEvidenceSourceRouting) for (const j of js) if ('evidence_source' in j && !SUPPORTED_EVIDENCE_SOURCES.includes(j.evidence_source)) return STOP('S-7', 'S7_UNSUPPORTED_EVIDENCE_SOURCE', String(j.evidence_source));
  // H2: only the NEW cleared+status=voided overlap is a Phase-0 FAIL-STOP (committed voided+status combos stay a Phase-1
  //     HOLD via the committed contradictory-state check; the unsupported-resolution_type FAIL-STOP is owned by S-4).
  for (const c of commits) if (c.resolution_type === 'cleared' && c.status === 'voided') return STOP('S-7', 'S7_CONTRADICTORY_STATE', c.expected_item_id);
  // G9/H3: legacy content gates apply to ACTIVE (non-superseded) records only; superseded records are inert audit.
  if (!mut.ignoreLegacyAuthority) for (const j of js) if (j.evidence_source === 'legacy_adjudication' && j.superseded !== true) {
    if (!PINNED_LEGACY_COMMITMENTS.includes(j.commitment_expected_item_id)) return STOP('S-7', 'S7_LEGACY_COMMITMENT_NOT_PINNED', j.commitment_expected_item_id);
    if (!LEGACY_DISPOSITION_VOCAB.includes(j.disposition)) return STOP('S-7', 'S7_UNSUPPORTED_DISPOSITION', String(j.disposition));
    if (!isValidSubjectId(j.adjudicated_by_subject_id)) return STOP('S-7', 'S7_ADJUDICATION_AUTHORITY_INVALID', typeof j.adjudicated_by_subject_id);
    if (j.adjudicated_by_subject_id !== AUTHORIZED_OWNER_SUBJECT_ID) return STOP('S-7', 'S7_ADJUDICATION_AUTHORITY_UNAUTHORIZED', j.adjudicated_by_subject_id);
    if (!mut.acceptForgedAdjudication && recomputeRecordDigest(j) !== j.record_digest) return STOP('S-7', 'S7_ADJUDICATION_DIGEST_MISMATCH', j.commitment_expected_item_id);
    const registry = mut.testAcceptedRegistry || ACCEPTED_LEGACY_RECORD_DIGESTS;
    if (!registry.includes(j.record_digest)) return STOP('S-7', 'S7_ADJUDICATION_NOT_IN_REGISTRY', j.commitment_expected_item_id);
  }
  // F10/G9: supersession chain structure over the FULL chain — single active tail per commitment; no cycle/self-supersede.
  const legacyByCommit = new Map();
  for (const j of js) if (j.evidence_source === 'legacy_adjudication') (legacyByCommit.get(j.commitment_expected_item_id) || legacyByCommit.set(j.commitment_expected_item_id, []).get(j.commitment_expected_item_id)).push(j);
  for (const [cid, recs] of legacyByCommit) {
    if (!mut.ignoreSupersessionStructure) {
      const bySup = new Map(recs.map((r) => [r.record_digest, r.supersedes]));
      for (const r of recs) if (r.supersedes != null && r.supersedes === r.record_digest) return STOP('S-7', 'S7_SUPERSESSION_CYCLE', cid);
      for (const start of bySup.keys()) { const seen = new Set(); let cur = start; while (cur != null && bySup.has(cur)) { if (seen.has(cur)) return STOP('S-7', 'S7_SUPERSESSION_CYCLE', cid); seen.add(cur); cur = bySup.get(cur); } }
    }
    if (!mut.ignoreMultipleActive && recs.filter((r) => r.superseded !== true).length > 1) return STOP('S-7', 'S7_MULTIPLE_ACTIVE_ADJUDICATIONS', cid);
  }
  // G5/G8: cross-lane / durable transaction reuse — a clearing txn bound to >1 DISTINCT commitment where at least one
  //   binding is via a J (au11/legacy lane) FAIL-STOPs. Two commitment-DB bindings of one txn are S-4's domain
  //   (S4_DUPLICATE_CLEARING_LINKAGE), not this check. Same-lane in-package duplicate is the committed HOLD below (G5).
  if (!mut.ignoreCrossLaneReuse) {
    const use = new Map(); const jTxns = new Set();
    const bind = (txn, cid) => { if (txn == null) return; (use.get(txn) || use.set(txn, new Set()).get(txn)).add(cid); };
    for (const c of commits) bind(c.cleared_transaction_id, c.expected_item_id);
    for (const j of js) if (j.superseded !== true && j.cleared_transaction_id != null) { bind(j.cleared_transaction_id, j.commitment_expected_item_id); jTxns.add(j.cleared_transaction_id); }
    for (const [txn, cids] of use) if (cids.size > 1 && jTxns.has(txn)) return STOP('S-7', 'S7_CLEARING_TXN_REUSE_CONFLICT', txn);
  }

  // orphan J: evidence with no matching F commitment (committed)
  for (const j of js) if (!commitIds.has(j.commitment_expected_item_id)) return HOLD('S-7', 'S7_ORPHAN_EVIDENCE', j.commitment_expected_item_id);

  // ── PHASE 1 — per-commitment acceptance (committed logic + additive v3.1 extensions) ──
  const jByCommit = new Map();
  for (const j of js) (jByCommit.get(j.commitment_expected_item_id) || jByCommit.set(j.commitment_expected_item_id, []).get(j.commitment_expected_item_id)).push(j);
  const seenEv = new Set();
  for (const c of commits) {
    if (!releasedPredicate(c, evw, mut)) continue;          // G1 shared predicate
    if (mut.terminalNoEvidence) continue;                   // MUT: accept release without evidence
    const activeJs = (jByCommit.get(c.expected_item_id) || []).filter((j) => j.superseded !== true);
    if (activeJs.length === 0) return HOLD('S-7', 'S7_RELEASE_NO_EVIDENCE', c.expected_item_id); // release, no active J -> HOLD (SP-79)
    const j = activeJs[0];
    // contradictory terminal state (committed HOLD; the NEW cleared+voided overlap already FAIL-STOPPED in Phase 0)
    if ((c.resolution_type === 'voided' && c.status != null && c.status !== 'voided') || (c.status === 'voided' && c.resolution_type != null && c.resolution_type !== 'voided')) return HOLD('S-7', 'S7_CONTRADICTORY_STATE', c.expected_item_id);
    if (j.resolution_stale === true) return HOLD('S-7', 'S7_STALE_RESOLUTION', c.expected_item_id);
    // F-3: legacy disposition outcomes gate BEFORE any clearing evidence — a fully-formed clearing record can NOT make
    //   an unresolved_hold or a voided_or_never_cleared release capacity. (Reachable only for a registry-accepted active
    //   legacy record; pre-freeze the empty registry fail-stops it earlier in Phase 0.)
    if (j.evidence_source === 'legacy_adjudication' && !mut.ignoreLegacyDisposition) {
      if (j.disposition === 'unresolved_hold') return HOLD('S-7', 'S7_UNRESOLVED_LEGACY', c.expected_item_id);
      if (j.disposition === 'voided_or_never_cleared') return HOLD('S-7', 'S7_RELEASE_NOT_CLEARED', c.expected_item_id);
    }
    const evPresent = typeof j.resolution_evidence === 'string' && j.resolution_evidence.length > 0;
    if (!evPresent) return HOLD('S-7', 'S7_RELEASE_NO_EVIDENCE', c.expected_item_id);
    // requiredType (v3.1): null-on-release -> UNDETERMINED (only reachable when an active J exists); else the
    //   authoritative resolution->type map (cleared/reflected -> bank_cleared). Committed voided/paid_from_other map to
    //   the committed void_cancellation/alternate_payment, so committed fixtures are unchanged.
    if (c.resolution_type == null && !mut.ignoreResolutionUndetermined) return HOLD('S-7', 'S7_RESOLUTION_TYPE_UNDETERMINED', c.expected_item_id);
    const requiredType = REQUIRED_EVIDENCE_TYPE_BY_RESOLUTION[c.resolution_type] || 'void_cancellation';
    if (!mut.untypedEvidence && (typeof j.resolution_evidence_type !== 'string' || j.resolution_evidence_type.length === 0)) return HOLD('S-7', 'S7_EVIDENCE_TYPE_MISSING', c.expected_item_id);
    if (!mut.untypedEvidence && j.resolution_evidence_type !== requiredType) return HOLD('S-7', 'S7_EVIDENCE_WRONG_TYPE', `${c.expected_item_id}:${j.resolution_evidence_type}`);
    if (j.amount_cents != null && j.amount_cents !== c.amount_cents) return HOLD('S-7', 'S7_AMOUNT_MISMATCH', c.expected_item_id);
    if (j.source_account != null && j.source_account !== c.source_account) return HOLD('S-7', 'S7_SOURCE_MISMATCH', c.expected_item_id);
    if (j.resolution_type != null && c.resolution_type != null && j.resolution_type !== c.resolution_type) return HOLD('S-7', 'S7_RESOLUTION_TYPE_MISMATCH', c.expected_item_id);
    // H1/G3: a durable cleared_transaction_id is demanded ONLY for bank_cleared, or a LEGACY-branch alternate_payment.
    //   An absent-source (committed) alternate_payment keeps committed semantics -> not demanded (preserves PF-43).
    const needsDurableId = requiredType === 'bank_cleared' || (requiredType === 'alternate_payment' && j.evidence_source === 'legacy_adjudication');
    if (needsDurableId && j.cleared_transaction_id == null) return HOLD('S-7', 'S7_RELEASE_NO_EVIDENCE', c.expected_item_id);
    // committed UNCONDITIONAL clearing-metadata check (G4): fires whenever cleared_transaction_id != null, ANY type/source.
    if (j.cleared_transaction_id != null && !mut.acceptBareClearing) {
      for (const f of ['cleared_amount_cents', 'cleared_source_account', 'cleared_state', 'cleared_as_of']) if (j[f] == null) return HOLD('S-7', 'S7_CLEARING_METADATA_MISSING', `${c.expected_item_id}.${f}`);
      if (j.cleared_amount_cents !== c.amount_cents) return HOLD('S-7', 'S7_CLEARING_AMOUNT_MISMATCH', c.expected_item_id);
      // N-2: an alternate_payment clears from a DIFFERENT account, so its self-reported source is validated against the
      //   referenced Register row below, not against the commitment source here (bank_cleared/void keep committed check).
      if (requiredType !== 'alternate_payment' && j.cleared_source_account !== c.source_account) return HOLD('S-7', 'S7_CLEARING_SOURCE_MISMATCH', c.expected_item_id);
    }
    // Durable Register binding for a bank_cleared release OR a legacy alternate_payment carrying a cleared_transaction_id
    //   (N-2). The referenced row is AUTHORITATIVE — it must exist (F-1), not be a transfer leg (N-1), match the
    //   recomputed digest (F-1), agree on amount/direction/state and on source per lane (N-2), not also be an active
    //   pending deduction (N-4), lie within the window (F-2), and bind cleared_as_of to its transaction_date (N-3).
    if (needsDurableId && j.cleared_transaction_id != null && !mut.acceptBareClearing) {
      const matches = registerRows.filter((r) => r.txn_id === j.cleared_transaction_id);
      if (!mut.ignoreClearingTxnExistence) {
        if (matches.length === 0) return HOLD('S-7', 'S7_CLEARING_TXN_NOT_FOUND', `${c.expected_item_id}:${j.cleared_transaction_id}`);
        if (matches.length > 1) return STOP('S-7', 'S7_CLEARING_TXN_AMBIGUOUS', j.cleared_transaction_id); // P-6 also fail-stops a duplicate register txn_id
      }
      const tx = matches[0];
      // N-1: a transfer leg (an internal movement) can NEVER satisfy a durable clearing — aligns with XC_TRANSFER_ALSO_CLEARING.
      if (tx && tx.is_transfer_leg === true && !mut.ignoreS7TransferLeg) return STOP('S-7', 'S7_CLEARING_TXN_IS_TRANSFER', `${c.expected_item_id}:${j.cleared_transaction_id}`);
      if (tx && !mut.ignoreClearingTxnDigest) {
        if (j.cleared_transaction_digest == null) return HOLD('S-7', 'S7_CLEARING_METADATA_MISSING', `${c.expected_item_id}.cleared_transaction_digest`);
        if (j.cleared_transaction_digest !== recomputeClearingDigest(tx)) return HOLD('S-7', 'S7_CLEARING_DIGEST_MISMATCH', c.expected_item_id);
      }
      if (tx && !mut.ignoreClearingTxnBinding) {
        if (Math.abs(tx.amount_cents) !== c.amount_cents) return HOLD('S-7', 'S7_CLEARING_AMOUNT_MISMATCH', c.expected_item_id);
        if (!(typeof tx.amount_cents === 'number' && tx.amount_cents < 0)) return HOLD('S-7', 'S7_CLEARING_DIRECTION_INVALID', c.expected_item_id);
        if (tx.cleared !== true) return HOLD('S-7', 'S7_CLEARING_STATE_INVALID', c.expected_item_id);
        // source: bank_cleared clears from the commitment's own account; alternate_payment clears from a DIFFERENT
        //   account, validated against the J's declared paying account (N-2) — never trusted as a bare id.
        if (requiredType === 'bank_cleared') { if (tx.account_key !== c.source_account) return HOLD('S-7', 'S7_CLEARING_SOURCE_MISMATCH', c.expected_item_id); }
        else if (tx.account_key !== j.cleared_source_account || tx.account_key === c.source_account) return HOLD('S-7', 'S7_CLEARING_SOURCE_MISMATCH', c.expected_item_id);
      }
      // N-4: a durable clearing txn must not also be an active pending deduction (contradictory economic representation).
      if (tx && !mut.ignorePendingClearingConflict && arr(pkg, 'pending_or_uncleared_evidence').some((p) => p.txn_id === j.cleared_transaction_id && p.represented_as_deduction === true)) return STOP('S-7', 'S7_CLEARING_TXN_ALSO_DEDUCTED', j.cleared_transaction_id);
      // F-2: cleared_as_of must parse; N-5 splits the window into isolated lower/upper guards.
      const asof = parseUtcInstant(j.cleared_as_of);
      if (asof == null) return HOLD('S-7', 'S7_CLEARING_ASOF_UNPARSEABLE', c.expected_item_id);
      const win = (pkg.execution_identity || {}).extraction_window || {};
      const winStart = parseUtcInstant(win.start), winEnd = parseUtcInstant(win.end);
      // F-2: S-7 OWNS this window check (P-2 never reads cleared_as_of). The preflight lacks the model-week->date epoch,
      //   so the extraction-window START is the deterministic, fail-closed release floor and the END the upper bound
      //   (both inclusive). N-3 additionally binds cleared_as_of to the referenced row's authoritative transaction_date.
      if (winStart != null && !mut.ignoreClearingAsofLower && asof < winStart) return HOLD('S-7', 'S7_CLEARING_ASOF_OUT_OF_WINDOW', `${c.expected_item_id}:before`);
      if (winEnd != null && !mut.ignoreClearingAsofUpper && asof > winEnd) return HOLD('S-7', 'S7_CLEARING_ASOF_OUT_OF_WINDOW', `${c.expected_item_id}:after`);
      if (tx && !mut.ignoreClearingDateBinding) { // N-3: EXACT (non-heuristic) binding to the referenced row's transaction_date
        if (tx.transaction_date == null) return HOLD('S-7', 'S7_CLEARING_ROW_DATE_MISSING', c.expected_item_id);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(tx.transaction_date)) return HOLD('S-7', 'S7_CLEARING_ROW_DATE_MALFORMED', `${c.expected_item_id}:${tx.transaction_date}`);
        if (j.cleared_as_of.slice(0, 10) !== tx.transaction_date) return HOLD('S-7', 'S7_CLEARING_ASOF_ROW_MISMATCH', c.expected_item_id);
      }
    }
    // evidence-identity reuse across commitments (committed same-lane in-package duplicate -> HOLD, G5)
    const evId = j.resolution_evidence_id ?? j.cleared_transaction_id;
    if (evId != null) { if (seenEv.has(evId)) return HOLD('S-7', 'S7_DUPLICATE_EVIDENCE', evId); seenEv.add(evId); }
  }
  return PASS('S-7');
}

// ── XC cross-control consistency (derived fields must not contradict records; cross-section reconciliation) ──
export function XC_crossControl(pkg, mut) {
  if (mut.ignoreCrossControl) return PASS('XC');
  // three-way count reconciliation: attestation.rows_returned == section length == manifest query row_count
  const manifest = arr(pkg, 'source_query_manifest');
  for (const [rel, sec] of Object.entries(ATTEST_TO_SECTION)) {
    if (rel === 'source_query_manifest') continue;
    const a = (pkg.completeness_attestations || {})[rel]; if (!a) continue;
    const relName = SECTION_TO_RELATION[sec]; const q = manifest.find((x) => x.relation === relName);
    if (q && a.rows_returned != null && q.row_count !== a.rows_returned) return HOLD('XC', 'XC_COUNT_CONTRADICTION', `${rel}:att${a.rows_returned}!=q${q.row_count}`);
  }
  // a transfer leg txn must not ALSO appear as a pending deduction or a commitment clearing txn (cross-path double)
  const legIds = new Set(arr(pkg, 'register_transaction_evidence').filter((t) => t.is_transfer_leg).map((t) => t.txn_id));
  for (const p of arr(pkg, 'pending_or_uncleared_evidence')) if (p.represented_as_deduction && legIds.has(p.txn_id)) return STOP('XC', 'XC_TRANSFER_ALSO_DEDUCTED', p.txn_id);
  for (const c of arr(pkg, 'cash_commitment_evidence')) if (c.cleared_transaction_id != null && legIds.has(c.cleared_transaction_id)) return STOP('XC', 'XC_TRANSFER_ALSO_CLEARING', c.cleared_transaction_id);
  // N-1: the transfer-leg-as-clearing prohibition also covers the J lane (terminal-resolution cleared_transaction_id),
  //   so S-7 and XC agree on ONE transfer-leg interpretation across both the commitment-lane and J-lane bindings.
  if (!mut.ignoreXcJLaneTransfer) for (const j of arr(pkg, 'terminal_resolution_evidence')) if (j.cleared_transaction_id != null && legIds.has(j.cleared_transaction_id)) return STOP('XC', 'XC_TRANSFER_ALSO_CLEARING', j.cleared_transaction_id);
  // a self-asserted derived field must match the records it summarizes (H4: shares the S-7 released predicate so a
  // `cleared`/`reflected` claimed_released commitment is not falsely contradicted at package-rebuild time).
  for (const c of arr(pkg, 'cash_commitment_evidence')) if (c.claimed_released === true) {
    if (!releasedPredicate(c, evalWeek(pkg), mut)) return HOLD('XC', 'XC_DERIVED_FIELD_CONTRADICTION', c.expected_item_id);
  }
  return PASS('XC');
}

// Ordered registry (P/structural before S; XC last so it reconciles across the others).
export const CONTROLS = [
  { key: 'environment_certified', fn: P1_environment },
  { key: 'as_of_coherent', fn: P2_asOf },
  { key: 'schema_compatible', fn: P3_schema },
  { key: 'evidence_integrity_verified', fn: P4_integrity },
  { key: 'cardinality_reconciled', fn: P5_cardinality },
  { key: 'query_provenance_complete', fn: PQ_provenance },
  { key: 'identity_unique', fn: P6_uniqueness },
  { key: 'economic_identity_authoritative', fn: P7_economicIdentity },
  { key: 'transfer_treatment_valid', fn: P8_transfer },
  { key: 'balance_authoritative', fn: P9_balance },
  { key: 'authoritative_checking_anchor_present', fn: AN_anchor },
  { key: 'off_model_obligations_authoritative', fn: S1_offModel },
  { key: 'reconciliation_not_null', fn: S2_nullRecon },
  { key: 'reconciliation_unique', fn: S3_dupRecon },
  { key: 'commitments_valid', fn: S4_commitments },
  { key: 'uncleared_items_reconciled', fn: S5_uncleared },
  { key: 'obligation_set_complete', fn: S6_completeness },
  { key: 'reserve_release_evidence_complete', fn: S7_reserveRelease },
  { key: 'cross_control_consistency_verified', fn: XC_crossControl },
];
