# 2027 Rollover Package C: server package (D-11)

| | |
|---|---|
| Governing specification | `docs/rollover-2027-spec.md`, frozen v2.1 (SHA-256 `b8443406…cf57`), §7.1-§7.5, §10, §13 T-SRV |
| Base | Package B, `4fc2588` |
| Server package | `docs/rollover-2027-server-package-c.sql`: authored and tested locally only. Not applied anywhere |
| Tests | `test_rollover_server.js` (hermetic PostgreSQL), registry entries T-SRV-1 to T-SRV-12, T-SRV-15 to T-SRV-17, X-N9 |
| OWNER HOLD | ON (`GOAL_FUNDING_OWNER_AUTHORITY` = `NOT_AUTHORIZED`, unchanged) |

## 1. Contract ownership correction

T-SRV-13 (reversal after the first close aborts) and T-SRV-14 (initialization: all-or-nothing, postflight IP-1 to IP-7, manifest) moved from Package C to Package F by owner ruling, 2026-10-07. **The frozen contract remains unchanged; package ownership was corrected because initialization/reversal implementation belongs to Package F.**

Package C owns 16 contracts. No Package F implementation was done. The first-close side of T-SRV-14 (f), (f2) and (g) is exercised here through T-SRV-2 and T-SRV-16, with opening anchors written directly by the test fixture.

## 2. Test environment

- PostgreSQL 17.11 (Homebrew), the same major version as production (`docs/environment-manifest.md`: 17.6).
- `tools/rollover-pg.js` creates a throwaway cluster in a new temp directory, reachable only through a Unix socket (`listen_addresses=''`), and deletes it afterwards. It never connects to Supabase, staging or production.
- **Real objects:** each base table and function is extracted verbatim from the repository migration that created it. Loading them reproduces the recorded production `md5(pg_get_functiondef)` exactly for the wrapper (`e2a112b3…`), the reconciliation RPC (`1bfde751…`) and the snapshot RPC (`154231b3…`). `correct_goal_funding_snapshot` and `validate_commitment_state` have one repository definition each and no recorded pin.
- **Stand-ins** (`fixtures/rollover/server/standins.sql`): the `anon` and `authenticated` roles, `auth.users`/`auth.uid()`, the three role helpers (driven by a test setting), and minimal `goal_registry` and `weekly_reconciliations` tables holding only the columns these functions read. RLS and grants other than the new helpers' are not reproduced; no Package C contract depends on them.
- All data is synthetic. The 2026 goal identifiers are the nine the deployed wrapper hard-codes; amounts are generated.

```bash
node test_rollover_server.js
```

```bash
node test_rollover_server.js --baseline
```

The second command runs the same tests against the Package B baseline (no Package C SQL) and is the RED evidence.

## 3. What the server package changes

All within §10. Function signatures are unchanged, so owners and grants carry over.

| Object | Change |
|---|---|
| `plan_year_of_week(int)`, `opening_week_of_plan(int)` | New immutable helpers (§3). EXECUTE revoked from PUBLIC, anon and authenticated (N-9); no grant |
| `cash_commitments` | Week checks ≥ 1; P-Y1 check |
| `goal_funding_snapshots` | Week check ≥ 1; P-Y2 check |
| `validate_commitment_state` | Week ≥ 1 |
| `save_reconciliation_with_commitments` | P-Y3; week ≥ 1; patches may reach earlier plan years (`model_year ≤ p_model_year`), never later ones |
| `save_goal_funding_snapshots` | Week ≥ 1; never writes at the opening position, so with P-Y2 it can never write an `opening_anchor` row (O2) |
| `save_weekly_closeout_with_snapshots` | P-Y3; eligibility from R(Y) by derive → lock → re-derive; archived contradiction; proven global contiguity; first-close re-verification; global latest week for reopen; reads and writes scoped to `p_model_year` |
| `correct_goal_funding_snapshot` | P-Y3; eligibility from R(Y); archived contradiction; rejects the opening position |

The advisory lock key, RLS, grants, other tables and `repair_commitments_for_week` are unchanged.

## 4. The first close, in plain terms

Every close now works out which goals it covers from the database, never from the client's list. It takes the existing per-week lock and reads R(Y): the goals with an opening anchor for that plan year. It locks those goals' registry rows in name order, then reads R(Y) again; if the set changed in between (an initialization or reversal ran), it stops. The submitted rows must cover exactly that set.

Only the first close of a plan from 2027 on (week 31 for 2027) does more, and only as a new close or a half-close repair, never as a retry or a reopen. It share-locks exactly the previous plan's tracked goals, in name order, so no correction, reopen or reversal can change them while it checks, and then checks from the database:

- every opening anchor note follows the grammar `new`, `carry:<id>` or `carry:<id>;reason=<text>`, where the reason must contain a non-whitespace character (§7.4: "An empty reason is not permitted"; owner ruling NB-1, 2026-10-08);
- IP-2: each anchor's goal exists and is not archived;
- IP-3: no 2027 goal has a 2026 snapshot;
- IP-4 and IP-6: every 2026 tracked goal is carried by exactly one successor or closed as `executed` or `archived`, never both and never neither; a successor names only a 2026 tracked goal;
- IP-5: a carried opening value equals the predecessor's final week-30 value unless the note states a reason.

Any failure raises, and PostgreSQL rolls back the whole call: nothing is written.

## 5. Evidence

RED (Package B baseline): 14 of 16 contracts fail for the intended reason. T-SRV-1 and T-SRV-7 are **preservation contracts, green at baseline**: the deployed wrapper already closes week 30 as 2026 while 2027 anchors exist, and its patch scope already refuses another plan year's commitment. Package C must keep both true, and does.

GREEN (Package C): 16 of 16 contracts, plus nine supporting tests (not contracts):

| Test | Pins |
|---|---|
| `PKGC-ATOMIC` | A first close that fails after its reconciliation and commitment writes leaves the database exactly as before |
| `PKGC-2026-PARITY` | 23 2026 calls (close, retry, GFA01, monotonic, reopen, repair, correction, role and input rejections) give the same outcomes and final state as the baseline |
| `PKGC-NB1-BLANK-REASON` | `reason=` followed only by spaces or tabs fails the grammar; a nonblank reason passes |
| `PKGC-NEVER-BOTH` | A carried predecessor with status `executed` or `archived` fails IP-4 |
| `PKGC-LATER-CLOSE` | The week-32 close does not rerun the first-close checks |
| `PKGC-2028-BOUNDARY` | Week 82 closes as 2027 only; week 83 needs 2028 opening state at week 82, then closes; a 2028 anchor at week 83 is rejected |
| `PKGC-HELPER-MIRROR` | The SQL helpers equal the §3 oracle (`tools/rollover-test-kit.js` `cal`) over weeks 1-1500 and plans 2026-2055. The client mirror itself arrives in Package D (T-ID-2) |
| `PKGC-W30-HALF-CLOSED` | A first close over a half-closed week 30 is refused until the week-30 repair, then succeeds |
| `PKGC-NEW-COMMITMENT-2027` | A commitment created at the week-31 close is plan 2027, origin 31; a plan-2026 one is refused |

T-SRV-17 uses two real database sessions: a close holding its locks makes a 2026 correction and a week-30 reopen wait and then resolve in serial order; a correction or reversal first makes the close wait and then fail closed; lock probes show R(2027) held `FOR UPDATE`, exactly R(2026) held `FOR SHARE`, and other goals unlocked. The reversal used there is a stand-in following §7.4's lock order and abort guard; the real reversal is Package F.

## 6. Deliberate breaks

Each control was broken alone in a scratch copy of the package and the full server suite rerun; the unbroken package stays green.

| # | Control removed or altered | Invariant it protects | Turned RED |
|---|---|---|---|
| C1 | Re-derive of R(Y) after locking | OD-4 step 4: no stale goal set | T-SRV-17 |
| C2 | `FOR UPDATE` on R(Y) | OD-4 step 3 | T-SRV-17 |
| C3 | `FOR SHARE` on R(Y−1) | OD-4 step 5: stable predecessor state | T-SRV-17 |
| C4 | `FOR SHARE` widened to the whole registry | OD-4 step 5: exactly R(Y−1) | T-SRV-17 |
| C5 | First-close re-verification disabled | §7.4 machine gate | T-SRV-16, T-SRV-17, PKGC-NB1, PKGC-NEVER-BOTH |
| C6 | Re-verification also on retry and reopen | OD-3 scope | T-SRV-16 |
| C7 | Re-verification skipped on half-close repair | OD-3 scope | T-SRV-16 |
| C8 | Client goal list trusted | Eligibility from R(Y), not the client | T-SRV-5 |
| C9 | R(Y) without the `opening_anchor` filter | §7.1 R(Y) source filter | T-SRV-16 |
| C10 | Gap check removed | Proven global contiguity | T-SRV-3 |
| C11 | P-Y3 removed from the wrapper | P-Y3 | T-SRV-4, T-SRV-12, PKGC-2028 |
| C12 | Patch scope back to the same plan year | Cross-year commitments (§8) | T-SRV-6, PKGC-ATOMIC |
| C14 | Snapshot function writes at the opening position | O2 | T-SRV-12 |
| C15 | Archived contradiction removed | §7.5 | T-SRV-15 |
| C16 | Correction at the opening position allowed | O2 | T-SRV-10 |
| C17 | P-Y1 check removed | P-Y1 | T-SRV-8 |
| C18 | P-Y2 check removed | P-Y2 | T-SRV-8, T-SRV-12, PKGC-2028 |
| C19 | IP-5 stated-reason bypass | IP-5 | T-SRV-16, T-SRV-17 |
| C20 | Anchor-note grammar loosened | §7.4 grammar | T-SRV-16, PKGC-NB1 |
| C21 | IP-4/IP-6 closed-status check removed | IP-4, IP-6 | T-SRV-16 |
| C22 | IP-3 removed | IP-3 | T-SRV-16 |
| C23 | Helper EXECUTE not revoked | N-9 | X-N9 |
| C24 | Monotonic prior not scoped to the plan year | Monotonic against the opening snapshot | T-SRV-2, -5, -6, -9, -10, -11, -12, -16, -17 and five supporting tests |
| C25 | Whitespace-only reason accepted (pre-NB-1 grammar) | NB-1 | PKGC-NB1 |
| C26 | IP-4 "never both" removed | IP-4 | PKGC-NEVER-BOTH |
| C27 | First-close checks on every 2027+ close | OD-3: transition only | PKGC-LATER-CLOSE |

**Surviving break, resolved.** C13 (the snapshot function's separate "refuse `opening_anchor` source" predicate removed) survived the first run. That predicate was redundant: P-Y2 places every `opening_anchor` row at the opening position, which the function already refuses. The predicate was removed, the opening-position rule keeps the behavior protected, and T-SRV-12 now also proves an `opening_anchor` row cannot be written outside the opening position (it fails `chk_gfs_plan_year`).

## 7. Independent review

Fable, 2026-10-08: **PASS WITH NON-BLOCKING FINDINGS**, no required changes. Owner dispositions: NB-1 fixed (above); NB-7 (`public.` prefixes) and NB-8 (literal 6, as §10 writes it) not changed; NB-9 recorded (section 6); NB-10 (R(2026) derived from data) and NB-11 (changed 2026 error wording; the client matches only `GFA01`) accepted as specified; NB-2 to NB-6 carried to Packages F and G (section 9).

## 8. Findings for owner review

1. **IP-4 "never both" (owner ruling 2026-10-07: approved).** A carried predecessor whose status is `executed` or `archived` is treated as both carried and closed, and fails: a successor cannot carry funded state from a predecessor that has already been disposed.
2. **Gap scope (owner ruling 2026-10-07: approved).** A gap blocks a new close and an idempotent retry; the half-close repair of the earliest incomplete week still runs, provided every earlier week is complete (T-SRV-3). The repair condition is now "every earlier week complete" instead of a count, which is the same when there is no gap.
3. **Snapshot function hardening.** Under O2 the snapshot function now refuses the opening position from any caller. A separate "refuse `opening_anchor` source" predicate was written first and removed: the deliberate-break run showed it redundant, because P-Y2 places every `opening_anchor` row at the opening position.
4. **Client role writes.** Direct client inserts into the two tables would now also fail the new checks, because the helpers are not executable by client roles. That is fail-closed, and clients are not meant to write these tables.
5. **Server suite gate (owner ruling 2026-10-07).** `test_rollover_server.js` stays out of the general pre-push hook, because it needs a local PostgreSQL server. It is **mandatory** for Package C commit, push and release review, and again for the applicable Package G server validation.
6. **Apply-time guard (Package G).** Before applying this package, verify the live bodies equal the base hashes in the file header; two functions have no recorded production pin.
7. **Helper names (owner ruling 2026-10-07: approved).** `plan_year_of_week(int)` and `opening_week_of_plan(int)`.

## 9. Carried obligations (not implemented in Package C)

**Package F** (T-SRV-13 and T-SRV-14 remain Package F, PENDING):
- **F-C1 (NB-1):** initialization and its preflight use the same nonblank-reason rule; a whitespace-only reason is invalid.
- **F-C2 (NB-2):** the reversal takes the required plan-Y registry locks (§7.4 OD-4 order) before deleting opening anchors; raw SQL deletion must not bypass the lock discipline Package C relies on.
- **F-C3 (NB-4):** the snapshot function refuses the opening position, so initialization owns the authorized direct creation of opening anchors.

**Package G** (rehearsal and deployment):
- **G-C1 (NB-6):** before replacing functions, verify the applying role owns the existing functions (so the new helpers get the same owner); fail before applying if not.
- **G-C2 (NB-5):** record the post-apply helper ACL and default-privilege posture, including any `service_role` EXECUTE, keeping N-9's denial to PUBLIC, anon and authenticated.
- **G-C3 (NB-3):** verify no unexpected or late opening anchors exist after the first close; treat one as an integrity finding, not something to absorb.
- **G-C4:** capture and verify the live bodies and hashes of all five replaced functions before applying; two have no recorded production hash.
- **G-C5:** after applying, compare function owner, security attributes, configuration and grants with the expected state.
- **G-C6:** exercise real RLS and roles for Adam and Wendy through the real client on isolated staging.
- **G-C7:** validate against the real `goal_registry` and `weekly_reconciliations` schema and data shape on isolated staging.
- **G-C8:** repeat the relevant two-session tests under Supabase connection pooling and timeouts.
- **G-C9:** run the §16 staging rehearsal and the 2026 parity proof before any production application.
