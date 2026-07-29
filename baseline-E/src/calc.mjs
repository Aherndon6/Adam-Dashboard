// baseline-E/src/calc.mjs
// Design ref: spec §9 (two projections, global trough, gated closed-form max-safe + self-verification),
// §10 (separated capacity), §12 (verdict taxonomy). Pure; integer cents; no clock/RNG; no discretionary sweeps.
//
// Event ordering (§14) and seam/candidate reconciliation (§5b/§5c) are UPSTREAM: this core consumes an already
// conservatively-ordered array of signed integer-cent deltas (inflow > 0, outflow < 0) for Projection A.

export const FLOOR_CENTS = 650000; // §2 CONTROL documented floor ($6,500); owner-confirmed (fail-closed) at execution.

function runningTrough(opening, deltas) {
  let bal = opening, min = opening;
  const balances = [];
  for (const d of deltas) { bal += d; balances.push(bal); if (bal < min) min = bal; }
  return { balances, trough: min, final: bal };
}

export function projectionTrough(opening_cents, deltas) {
  return runningTrough(opening_cents, deltas).trough;
}

// Insert the transfer as a single one-time debit (positive magnitude) at index p (§9 synthetic position).
function withTransfer(deltas, p, transferCents) {
  return [...deltas.slice(0, p), -transferCents, ...deltas.slice(p)];
}

// Full §9 analysis for a counterfactual Projection A + the gated max-safe solve + mandatory self-verification.
export function analyze({ opening_cents, eventsA, transfer_position, floor = FLOOR_CENTS, external_cap_cents = null }) {
  const a = runningTrough(opening_cents, eventsA);
  const troughA = a.trough;
  const p = transfer_position;

  // Pre-transfer balances = opening + every running balance strictly before the transfer position.
  const preBalances = [opening_cents, ...a.balances.slice(0, p)];
  const preTransferTrough = Math.min(...preBalances);
  const breach = preTransferTrough < floor; // §9 pre-transfer-breach gate

  // Synthetic transfer-position checkpoint = pre-debit running balance at p (§9, closes rev-4 ND-4).
  const checkpoint = opening_cents + eventsA.slice(0, p).reduce((s, d) => s + d, 0);
  const atAfter = [checkpoint, ...a.balances.slice(p)];
  const atAfterMin = Math.min(...atAfter);

  // Gated closed form: 0 on pre-transfer breach OR non-negativity clamp; else atAfterMin − floor.
  const maxSafe = breach ? 0 : Math.max(0, atAfterMin - floor);

  const troughAt = (T) => runningTrough(opening_cents, withTransfer(eventsA, p, T)).trough;

  // Mandatory self-verification (§9 three cases). FAIL-STOP only on a genuine A/B relationship violation.
  let selfVerify;
  if (external_cap_cents != null && external_cap_cents < maxSafe) {
    const atCap = troughAt(external_cap_cents);            // Case C: external cap binds below mechanical max
    selfVerify = { case: 'C', ok: atCap >= floor, atCap, binding: 'external_cap' };
  } else if (maxSafe > 0) {
    const atMax = troughAt(maxSafe);                       // Case A: trough exactly at floor; max+1¢ breaches
    const atMaxPlus = troughAt(maxSafe + 1);
    selfVerify = { case: 'A', ok: atMax === floor && atMaxPlus < floor, atMax, atMaxPlus };
  } else {
    const at0 = troughAt(0);                               // Case B: $0 reproduces Projection-A trough; PASS-UNSAFE
    const at1 = troughAt(1);
    selfVerify = {
      case: 'B',
      reason: breach ? 'pre_transfer_breach' : 'non_negativity_clamp',
      ok: at0 === troughA && at1 <= at0 && at1 < floor,    // not required to equal floor; must not improve; below floor
      at0, at1,
    };
  }

  return { floor, troughA, cushionA: troughA - floor, baseline_capacity: Math.max(0, troughA - floor),
           preTransferTrough, breach, checkpoint, atAfterMin, maxSafe, selfVerify };
}

// Verdict for a SUPPLIED proposed transfer (§9 mandatory Projection-B run; §12 taxonomy, calc-core subset:
// PASS-SAFE / PASS-UNSAFE only — HOLD / FAIL-STOP come from the input/reconciliation controls elsewhere).
export function verdictForTransfer({ opening_cents, eventsA, transfer_position, transfer_cents, floor = FLOOR_CENTS }) {
  const troughB = runningTrough(opening_cents, withTransfer(eventsA, transfer_position, transfer_cents)).trough;
  return { troughB, cushionB: troughB - floor, verdict: troughB >= floor ? 'PASS-SAFE' : 'PASS-UNSAFE' };
}
