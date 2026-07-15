# Disaster Recovery Exit Gate — DR-1 (July 2026)

**Status:** TEMPLATE — items to be evidenced + signed. **Mandatory pre-freeze exit gate.**
**Deadline:** all items evidenced + signed by **Jul 28, 2026 EOD** (day before the `Jul 29 – Aug 10` freeze).
**Sign-off:** Adam, dated, below. This record is **secrets-free and balance-free** — no credentials, no household balances.
**Authority:** `docs/roadmap/canonical-roadmap.md` §5. **Blocking effect:** DR-1 failure **blocks all post-5G-1D implementation work** (Register bundle, 1B build, 5G-2, extraction) until closed; if items slip, closing DR-1 is the first Aug-11 action, before any code. Does **not** retro-block the Jul 18 activation sitting or Wendy's operational use.

**Why mandatory:** the OS is the sole live system of record on a Free-plan database with no PITR, one operator, entering an 18-day absence. "Start now" without an exit criterion is how the #1 item stays 80% done.

---

## Gate items

### 1 — Database recovery
- [ ] Fresh production `pg_dump` (custom-format `-Fc`, `--no-owner --no-acl`, public schema) taken **after the last pre-freeze closeout** (post-Wk-6 on Jul 18; refresh post-Wk-7 on Jul 25).
- [ ] `pg_restore --list` verified restorable.
- [ ] `chmod 600`; SHA-256 recorded (in the metadata doc, not here).
- [ ] **Two encrypted off-device copies** (cloud + second physical device); transfer verified.
- [ ] Retention cadence documented: **8 weekly / 6 monthly + pre-close / pre-correction**.
- [ ] **AF-4:** periodic `git bundle` of all branches added to the same cadence + off-device set.

*Evidence:* dump metadata doc (Slice-6 pattern) — path: `__________`; SHA-256 recorded: [ ]; transfer-verified note: `__________`.

### 2 — Source recovery
- [ ] Post-merge `origin/main` == deployed build (commit hash: `__________`).
- [ ] Activation branch pushed.
- [ ] Repo cloneable from a second machine (verified: [ ]).
- [ ] `git bundle` (all branches) copied off-device encrypted.
- [ ] Local evidence directory (`~/Herndon-FOS-DB-Backups`, execution artifacts) copied off-device encrypted.

*Note:* Pages loss is tolerable (static app; any host can serve `index.html`) — bundle + DNS manifest is a complete source-recovery floor.

### 3 — Environment / configuration recovery
- [ ] `docs/environment-manifest.md` completed (secrets-free): Supabase project refs (prod `usayoldrawwmjsmretin`, staging `pkwotgqivgaapwuqgwqb`) + `system_identifier`s; GitHub Pages + CNAME (`dashboard.herndons.us`) + DNS provider pointer; the final post-Phase-2 grant matrix (operator package §4) as the restore target; RLS role-model pointer; `BUILD_TS` convention; anon-key rotation procedure pointer.

*Evidence:* `docs/environment-manifest.md` complete: [ ].

### 4 — Credential recovery
- [ ] Owner MFA enrolled (**after the Jul 18 sitting, before departure — never mid-trip**) + recovery codes stored in two locations, off-device.
- [ ] Backup-owner account created; login verified; role posture verified (financial write **yes**, `anthropic_key` **no**).
- [ ] Supabase org recovery email verified.
- [ ] Password manager holds Supabase / GitHub / DSN / backup-encryption / domain entries.

*Evidence (no secrets):* MFA enrolled + codes in two locations: [ ]; backup-owner test note: `__________`.

### 5 — Operational runbooks
- [ ] `docs/restore-runbook.md` drafted: DB restore, source redeploy, environment restore from manifest, credential recovery, **AF-1 full-project-loss auth re-link**, **AF-3 / A19 Supabase inactivity-pause unpause step**, derived-vs-observed doctrine.
- [ ] **One tabletop walkthrough** completed (date: `__________`).

### 6 — Accepted variance
- [ ] Trip-window posture recorded: no dumps `Jul 29 – Aug 10` (unless remote-capable), expiry Aug 11.
- [ ] Full staging **restore rehearsal** scheduled Aug 11–17 (may slide out of the gate, not out of the calendar).

---

## Absorbed wishlist items
8 (owner MFA) · 9 (backup owner) · 18 (data export & backup plan) · P6 (anon-key rotation → restore-runbook appendix).

## Related pre-departure verification
- [ ] **A19 / AF-3:** Supabase Free-plan inactivity-pause policy verified against **both** prod and staging (≤ Jul 25); unpause step documented in `docs/restore-runbook.md`. *Do not represent the policy as verified until supported by current evidence; no plan upgrade is implied.*

---

## Sign-off

| Field | Value |
|---|---|
| All items evidenced | [ ] |
| Signed by | Adam Herndon |
| Date | `__________` (≤ Jul 28, 2026) |
| Gate disposition | ☐ CLOSED ☐ CLOSED WITH ACCEPTED VARIANCE ☐ OPEN |

*Balance-free, secrets-free gate record. On sign-off, append a line to `docs/decision-log.md`.*
