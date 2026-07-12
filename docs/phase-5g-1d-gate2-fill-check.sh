#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# ██  STAGING ONLY — herndon-fos-staging  ██   Phase 5G-1D Gate 2 — LOCAL FILL-COPY workflow + placeholder guard.
# ═══════════════════════════════════════════════════════════════════════════
# ONE workflow so the operator never manually overlooks a placeholder across many files. Two modes:
#
#   init  <dest-dir>   Copy every committed gate2-*.sql/.sh into <dest-dir> as *.FILLED.local.* (chmod 600),
#                      so the operator edits ONLY local copies. Real values (FP-3 md5s, recorded_at literals,
#                      OWNER_UID, PATCH_ID, tokens/keys) go ONLY into these local copies — never committed.
#
#   check <dest-dir>   HARD-STOP scan: fail (exit 1) if ANY committed-style placeholder remains unresolved in
#                      the local filled copies — {{...}}, <ADAM_UID>, <WENDY_UID>. Run this BEFORE executing
#                      any filled SQL/HTTP so an overlooked placeholder can never reach a mutation.
#
# Run `check` after filling and again before each sub-phase. The committed files remain placeholder-only;
# this script never edits committed files. It executes NO SQL and NO HTTP.
# ─────────────────────────────────────────────────────────────────────────
set -uo pipefail
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the committed docs/ dir
PATTERN='\{\{[A-Za-z0-9_]+\}\}|<ADAM_UID>|<WENDY_UID>'

usage(){ echo "usage: $0 init <dest-dir> | $0 check <dest-dir>"; exit 2; }
[ $# -eq 2 ] || usage
mode="$1"; dest="$2"

case "$mode" in
  init)
    mkdir -p "$dest" || { echo "HARD STOP: cannot create $dest"; exit 1; }
    for f in "$SRC_DIR"/phase-5g-1d-gate2-*.sql "$SRC_DIR"/phase-5g-1d-gate2-exec-template.sh; do
      base="$(basename "$f")"; out="$dest/${base%.*}.FILLED.local.${base##*.}"
      cp "$f" "$out" && chmod 600 "$out" && echo "  copied → $out"
    done
    echo "FILL-COPY init done. Edit ONLY the *.FILLED.local.* files; fill placeholders; then: $0 check $dest"
    ;;
  check)
    [ -d "$dest" ] || { echo "HARD STOP: $dest is not a directory"; exit 1; }
    hits="$(grep -rnoE "$PATTERN" "$dest" 2>/dev/null)"
    if [ -n "$hits" ]; then
      echo "HARD STOP: unresolved placeholder(s) remain in local fill copies — fill them before executing:"
      printf '%s\n' "$hits" | sed 's/^/    /'
      exit 1
    fi
    echo "FILL-CHECK PASS: no unresolved {{...}} / <ADAM_UID> / <WENDY_UID> placeholders in $dest."
    ;;
  *) usage;;
esac
