# 5G-1D Slice 6 — Restore-Point Metadata (committable; metadata only)

Metadata-only record of the same-sitting production restore point captured immediately before the
Slice-6 migration. **The dump itself is local-only and never committed; no credentials, connection
strings, or household values appear here. Balance-free.** *(Committed under `docs/` because the
repo's `exports/` directory is git-ignored; the dump + `.list.txt` + `.evidence.txt` live local-only
under `~/Herndon-FOS-DB-Backups/Adam-Dashboard/5G-1D-Slice6/`.)*

- **Project:** Adam-Dashboard (`usayoldrawwmjsmretin`) — production
- **Purpose:** catastrophic disaster-recovery floor for Slice 6 (DR-only, **not** a routine Gate B /
  ACL rollback — F2). Captured before Slice 6 and before any Week-6 closeout, so it predates the
  first production write; restoring it after any post-dump write is a separately-approved DR action
  (Gate B runbook §7).
- **Scope:** public-schema `pg_dump`, custom format (`-Fc`), schema + DATA, `--no-owner --no-acl`
  (NOT a full Supabase platform backup).

## Local dump (never committed)

| Field | Value |
|---|---|
| Filename | `5G-1D-slice6-restorepoint-20260713T222223Z.dump` |
| Timestamp (UTC) | `20260713T222223Z` |
| Size | 182,028 bytes |
| Permissions | `-rw-------` (0600) |
| SHA-256 | `e3d24dfa6d1e8b94377f092ea405ea7b0385944cb1c6f3e59ed8da5dd9da8410` |
| `pg_dump` exit | 0 |
| `pg_restore --list` exit | 0 |
| Expected-object match | 4 / 4 (both tables + both deployed RPCs present) |
| Local location | `~/Herndon-FOS-DB-Backups/Adam-Dashboard/5G-1D-Slice6/` (outside the repo) |

## Encrypted off-device copy

| Field | Value |
|---|---|
| Location | iCloud Drive / Herndon-FOS-Backups / 5G-1D-Slice6 |
| Filename | `5G-1D-slice6-restorepoint-20260713T222223Z.dump.enc` |
| Encrypted SHA-256 | `8dc172d1e70c618bd8704d5612809233eaa99853aa25fc5c26035113630a69c9` |
| Post-transfer integrity | PASS (off-device copy SHA-256 verified) |
| Passphrase/key | stored separately from the encrypted file (not here, not in the repo) |

## DR restore conditions (if ever used, after any post-dump production write)

1. separate disaster-recovery approval;
2. explicit acknowledgement of the restore-point timestamp above;
3. a plan to preserve/replay post-dump data, or explicit acceptance of its loss;
4. verification that the restore scope will not overwrite valid later reconciliation/snapshot state.
