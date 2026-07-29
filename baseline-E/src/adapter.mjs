// baseline-E/src/adapter.mjs
// Design ref: spec §0(i) + §1a — pure effective-schedule merge reproducing reconEffectiveWD() semantics
// (index.html:2949-2965) over the pinned WD source + a read-only model_week_overrides snapshot.
//
// PRODUCTION-INDEPENDENT: this is the pure merge logic + duplicate detection. The real override snapshot
// (a read-only production read) and the mandated byte-for-byte differential-oracle validation against in-app
// reconEffectiveWD() are AUTHORIZED-CAPTURE-time steps and are NOT run here (see harness note + Mode-2 report).
//
// Semantics reproduced EXACTLY from source:
//  - events: effEvs = (ov.events_json && ov.events_json.length) ? ov.events_json : evs   (conditional; empty→literal)
//  - dates:  ov.dates || dates                          (independent)
//  - ct:     ov.ct != null ? ov.ct : ct                 (independent)
//  - ca:     ov.ca != null ? ov.ca : ca                 (independent)
//  - is_custom rows are APPENDED (sorted by week_num), never merged
//  - NO week_num de-duplication (the app collapses at load; the adapter reads RAW rows and flags duplicates)

function eventsToInOb(evs) {
  return {
    inflows: evs.filter(e => e.t === 'in').map(e => e.a),
    obs: evs.filter(e => e.t === 'ob').map(e => Math.abs(e.a)),
  };
}

// WD tuple shape: [num, dates, inflows[], obs[], evs[], ct, ca, note]
export function mergeEffectiveSchedule(WD, overrideRows = []) {
  const nonCustomByWeek = new Map();
  const custom = [];
  const duplicates = [];

  for (const ov of overrideRows) {
    if (ov.is_custom) { custom.push(ov); continue; }
    if (nonCustomByWeek.has(ov.week_num)) {
      duplicates.push({ week_num: ov.week_num, reason: 'duplicate non-custom override row for week (raw rows; not collapsed)' });
    } else {
      nonCustomByWeek.set(ov.week_num, ov);
    }
  }

  const effective = WD.map((wd) => {
    const [num, dates, , , evs, ct, ca, note] = wd;
    const ov = nonCustomByWeek.get(num);
    if (!ov) return { week_num: num, dates, evs, ...eventsToInOb(evs), ct, ca, note, source: 'wd_literal' };
    const effEvs = (ov.events_json && ov.events_json.length) ? ov.events_json : evs;
    return {
      week_num: num,
      dates: ov.dates || dates,
      evs: effEvs,
      ...eventsToInOb(effEvs),
      ct: ov.ct != null ? ov.ct : ct,
      ca: ov.ca != null ? ov.ca : ca,
      note,
      source: `override:${num}`,
      events_fallback: !(ov.events_json && ov.events_json.length), // true = empty override → literal events retained
    };
  });

  custom.slice().sort((a, b) => a.week_num - b.week_num).forEach((ov) => {
    const effEvs = ov.events_json || [];
    effective.push({
      week_num: ov.week_num, dates: ov.dates || 'Custom week', evs: effEvs, ...eventsToInOb(effEvs),
      ct: ov.ct || 0, ca: ov.ca || 0, note: '', source: 'custom',
    });
  });

  // Detect duplicate EFFECTIVE week numbers (e.g. a custom row sharing a base WD week) — never silently collapse (§13).
  const seen = new Map();
  for (const row of effective) seen.set(row.week_num, (seen.get(row.week_num) || 0) + 1);
  for (const [wk, n] of seen) if (n > 1) duplicates.push({ week_num: wk, reason: 'duplicate effective week_num (custom vs base) — requires adjudication / FAIL-STOP' });

  return { effective, duplicates, hasDuplicates: duplicates.length > 0 };
}
