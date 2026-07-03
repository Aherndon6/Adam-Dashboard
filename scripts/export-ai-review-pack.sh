#!/usr/bin/env bash
# scripts/export-ai-review-pack.sh
#
# Generates a portable markdown evidence pack for AI review (Claude/ChatGPT)
# when those tools lack direct filesystem access to this repo.
#
# Dev/review tooling only. Does not touch app files, schema, or tests.
# Written for bash 3.2 compatibility (macOS default /bin/bash).
#
# Note: intentionally does NOT use `set -u`. Empty-array expansion under
# `set -u` is unreliable in bash < 4.4 (macOS ships 3.2), so this script
# uses explicit emptiness checks instead of relying on -u to catch bugs.
set -eo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
DEFAULT_RISKY_KEYWORDS="budget_transactions,transactions,weekly_reconciliations,cash_commitments,save_reconciliation_with_commitments,p_patched,RLS,RPC,anthropic_key,service_role,balance_basis"
MAX_DOC_LINES=400

# Recursive grep exclusions are applied explicitly at each --exclude-dir
# call site below (not via a shared variable), per review decision.

# Secret-like regex patterns for the final redaction pass. Extended regex (grep -E / sed -E).
SECRET_PATTERNS=(
  'sk-ant-[A-Za-z0-9_-]*'
  'sk-[A-Za-z0-9]{20,}'
  'service_role["'"'"':= ]{1,4}[A-Za-z0-9._-]{16,80}'
  'SUPABASE_SERVICE_ROLE[A-Za-z0-9_]*["'"'"':= ]{1,4}[A-Za-z0-9._-]{16,80}'
  'ANTHROPIC_API_KEY["'"'"':= ]{1,4}[A-Za-z0-9._-]{16,80}'
  'OPENAI_API_KEY["'"'"':= ]{1,4}[A-Za-z0-9._-]{16,80}'
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  '[A-Za-z0-9+/]{80,}={0,2}'
)

# Human-readable labels, index-matched to SECRET_PATTERNS above. Used in the
# Redaction Summary instead of raw regex source, because printing the pattern
# text itself (e.g. containing the literal substring "sk-ant") can trip a
# downstream raw-secret grep check even though nothing was actually leaked.
SECRET_LABELS=(
  "anthropic-style-key"
  "generic-key-style-token"
  "service-role-key-value"
  "supabase-service-role-key"
  "anthropic-api-key-value"
  "openai-api-key-value"
  "jwt-style-token"
  "long-base64-like-string"
)

# ---------------------------------------------------------------------------
# Usage / arg parsing
# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
Usage: export-ai-review-pack.sh <phase> [--keywords "a,b,c"] [--commits "hash1,hash2"]

Example:
  scripts/export-ai-review-pack.sh 5F-1 \
    --keywords "5F,reconciliation,commitment" \
    --commits "be584c1,6d5c8b5"

Risky default keywords are always included automatically:
  budget_transactions, transactions, weekly_reconciliations, cash_commitments,
  save_reconciliation_with_commitments, p_patched, RLS, RPC, anthropic_key,
  service_role, balance_basis
EOF
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi

PHASE="$1"
shift
if [ -z "$PHASE" ]; then
  usage
fi

USER_KEYWORDS=""
COMMITS_RAW=""

while [ $# -gt 0 ]; do
  case "$1" in
    --keywords)
      if [ $# -lt 2 ]; then usage; fi
      USER_KEYWORDS="$2"
      shift 2
      ;;
    --commits)
      if [ $# -lt 2 ]; then usage; fi
      COMMITS_RAW="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Repo preflight checks (fail loudly, before writing anything)
# ---------------------------------------------------------------------------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository." >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ ! -f "AGENTS.md" ]; then
  echo "ERROR: required file AGENTS.md not found at repo root ($REPO_ROOT)." >&2
  exit 1
fi
if [ ! -f "CODEX_STATUS.md" ]; then
  echo "ERROR: required file CODEX_STATUS.md not found at repo root ($REPO_ROOT)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Normalize keyword list: user keywords + risky defaults, deduped, trimmed
# ---------------------------------------------------------------------------
COMBINED_RAW="$DEFAULT_RISKY_KEYWORDS"
if [ -n "$USER_KEYWORDS" ]; then
  COMBINED_RAW="$USER_KEYWORDS,$DEFAULT_RISKY_KEYWORDS"
fi

KEYWORDS=()
OLDIFS="$IFS"
IFS=','
for kw in $COMBINED_RAW; do
  kw_trimmed="$(printf '%s' "$kw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -z "$kw_trimmed" ]; then
    continue
  fi
  dup=0
  for existing in "${KEYWORDS[@]}"; do
    if [ "$existing" = "$kw_trimmed" ]; then
      dup=1
      break
    fi
  done
  if [ "$dup" -eq 0 ]; then
    KEYWORDS[${#KEYWORDS[@]}]="$kw_trimmed"
  fi
done
IFS="$OLDIFS"

# Build a single alternation pattern for grep -E once, reused everywhere.
KW_PATTERN=""
for kw in "${KEYWORDS[@]}"; do
  esc_kw="$(printf '%s' "$kw" | sed 's/[.[\*^$()+?{|]/\\&/g')"
  if [ -z "$KW_PATTERN" ]; then
    KW_PATTERN="$esc_kw"
  else
    KW_PATTERN="${KW_PATTERN}|${esc_kw}"
  fi
done

# ---------------------------------------------------------------------------
# Commit list: normalize, then validate every commit BEFORE writing anything
# ---------------------------------------------------------------------------
COMMITS=()
if [ -n "$COMMITS_RAW" ]; then
  OLDIFS="$IFS"
  IFS=','
  for c in $COMMITS_RAW; do
    c_trimmed="$(printf '%s' "$c" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -n "$c_trimmed" ]; then
      COMMITS[${#COMMITS[@]}]="$c_trimmed"
    fi
  done
  IFS="$OLDIFS"
fi

if [ "${#COMMITS[@]}" -gt 0 ]; then
  for c in "${COMMITS[@]}"; do
    if ! git cat-file -e "${c}^{commit}" 2>/dev/null; then
      echo "ERROR: commit not found or invalid: $c" >&2
      echo "No output pack was written." >&2
      exit 1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Prep output paths
# ---------------------------------------------------------------------------
mkdir -p exports
TS="$(date -u +%Y%m%d-%H%M%S)"
SAFE_PHASE="$(printf '%s' "$PHASE" | sed 's/[^A-Za-z0-9._-]/_/g')"
OUTFILE="exports/ai-review-pack-${SAFE_PHASE}-${TS}.md"
BODY_TMP="$(mktemp)"
FINAL_TMP="$(mktemp)"
trap 'rm -f "$BODY_TMP" "$FINAL_TMP"' EXIT
trap 'echo "ERROR: script failed at line ${LINENO}, last command: ${BASH_COMMAND}" >&2' ERR

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BRANCH="$(git branch --show-current)"
HEAD_SHA="$(git rev-parse HEAD)"
STATUS_SHORT="$(git status --short || true)"

DIRTY_WARNING=""
if [ -n "$STATUS_SHORT" ]; then
  DIRTY_WARNING="WARNING: working tree has uncommitted changes."
fi

DOC_MATCH_COUNT=0
GREP_SECTION_COUNT=0

# ---------------------------------------------------------------------------
# Grep helper that respects exclude dirs, never fails the script if 0 matches
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Build the body
# ---------------------------------------------------------------------------
{
  echo "# AI Review Evidence Pack"
  echo
  echo "**Phase:** ${PHASE}"
  echo
  echo "> This pack is a point-in-time snapshot. If repo files change after generation, regenerate before relying on it."
  echo
  if [ -n "$DIRTY_WARNING" ]; then
    echo "**${DIRTY_WARNING}**"
    echo
  fi

  echo "## Metadata"
  echo
  echo "- generated_at: ${GENERATED_AT}"
  echo "- repo_path: ${REPO_ROOT}"
  echo "- branch: ${BRANCH}"
  echo "- HEAD: ${HEAD_SHA}"
  echo "- phase: ${PHASE}"
  echo "- keywords: ${KEYWORDS[*]}"
  if [ "${#COMMITS[@]}" -gt 0 ]; then
    echo "- commits: ${COMMITS[*]}"
  else
    echo "- commits: (none supplied)"
  fi
  echo

  echo "## Pack Manifest"
  echo
  echo "- Git metadata: included"
  if [ "${#COMMITS[@]}" -gt 0 ]; then
    echo "- Commit evidence: included (${#COMMITS[@]} commit(s))"
  else
    echo "- Commit evidence: NOT SUPPLIED"
  fi
  echo "- AGENTS.md: included (full)"
  echo "- CODEX_STATUS.md: included (full)"
  echo "- Matching docs: see Matching docs/ section"
  echo "- Keyword grep results: see Keyword Grep Results section"
  echo "- Risky-keyword grep results: merged into keyword grep (risky defaults always included)"
  echo "- Redaction summary: included at end of pack"
  echo "- Missing/non-critical sections: flagged inline as NOT FOUND"
  echo
  echo "---"
  echo

  echo "## Git Status"
  echo
  echo '```'
  if [ -n "$STATUS_SHORT" ]; then
    echo "$STATUS_SHORT"
  else
    echo "(clean)"
  fi
  echo '```'
  echo

  echo "## Git Log (last 20)"
  echo
  echo '```'
  git log --oneline -20
  echo '```'
  echo

  echo "## Commit Evidence"
  echo
  if [ "${#COMMITS[@]}" -gt 0 ]; then
    for c in "${COMMITS[@]}"; do
      echo "### Commit: ${c}"
      echo
      echo '```'
      git show --stat "$c"
      echo '```'
      echo
      echo '```'
      git show --name-only --oneline "$c"
      echo '```'
      echo
    done
  else
    echo "**NOT FOUND** — no commits supplied."
    echo
  fi

  echo "---"
  echo
  echo "## AGENTS.md (full)"
  echo
  echo '```'
  cat AGENTS.md
  echo '```'
  echo

  echo "## CODEX_STATUS.md (full)"
  echo
  echo '```'
  cat CODEX_STATUS.md
  echo '```'
  echo

  echo "---"
  echo
  echo "## Matching docs/ files"
  echo

  if [ -d "docs" ] && [ -n "$KW_PATTERN" ]; then
    MATCHED_FILES="$(grep -rlE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=exports "$KW_PATTERN" docs/ 2>/dev/null || true)"
    PHASE_FILES="$(find docs -iname "*${PHASE}*" 2>/dev/null || true)"
    ALL_DOC_MATCHES="$(printf '%s\n%s\n' "$MATCHED_FILES" "$PHASE_FILES" | sed '/^$/d' | sort -u)"

    if [ -n "$ALL_DOC_MATCHES" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        DOC_MATCH_COUNT=$((DOC_MATCH_COUNT + 1))
        LINES="$(wc -l < "$f" | tr -d ' ')"
        echo "### ${f}"
        echo
        if [ "$LINES" -le "$MAX_DOC_LINES" ]; then
          echo '```'
          cat "$f"
          echo '```'
        else
          echo "_File exceeds ${MAX_DOC_LINES} lines (${LINES} lines). Showing keyword grep matches only._"
          echo
          echo '```'
          grep -nE "$KW_PATTERN" "$f" || echo "(matched by filename; no direct keyword line matches)"
          echo '```'
        fi
        echo
      done <<EOF_DOCS
$ALL_DOC_MATCHES
EOF_DOCS
    fi
  fi

  if [ "$DOC_MATCH_COUNT" -eq 0 ]; then
    echo "**NOT FOUND** — no docs/ files matched the supplied phase or keywords."
    echo
  fi

  echo "---"
  echo
  echo "## Keyword Grep Results"
  echo

  for target in index.html test_regression.js e2e.js; do
    echo "### ${target}"
    echo
    if [ -f "$target" ]; then
      GREP_SECTION_COUNT=$((GREP_SECTION_COUNT + 1))
      RESULT="$(grep -nE "$KW_PATTERN" "$target" 2>/dev/null || true)"
      if [ -n "$RESULT" ]; then
        echo '```'
        echo "$RESULT"
        echo '```'
      else
        echo "**NOT FOUND** — no keyword matches in ${target}."
      fi
    else
      echo "**NOT FOUND** — ${target} does not exist in this repo."
    fi
    echo
  done

  echo "### SQL/migration files"
  echo
  GREP_SECTION_COUNT=$((GREP_SECTION_COUNT + 1))
  SQL_MATCHES="$(grep -rnE --include='*.sql' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=exports "$KW_PATTERN" . 2>/dev/null || true)"
  if [ -n "$SQL_MATCHES" ]; then
    echo '```'
    echo "$SQL_MATCHES"
    echo '```'
  else
    echo "**NOT FOUND** — no SQL/migration matches, or no .sql files present in this repo."
  fi
  echo

  echo "### AGENTS.md / CODEX_STATUS.md keyword matches"
  echo
  GREP_SECTION_COUNT=$((GREP_SECTION_COUNT + 1))
  AC_MATCHES="$(grep -nE "$KW_PATTERN" AGENTS.md CODEX_STATUS.md 2>/dev/null || true)"
  if [ -n "$AC_MATCHES" ]; then
    echo '```'
    echo "$AC_MATCHES"
    echo '```'
  else
    echo "**NOT FOUND** — no keyword matches in AGENTS.md/CODEX_STATUS.md."
  fi
  echo

  echo "---"
  echo
  echo "> This pack is a point-in-time snapshot. If repo files change after generation, regenerate before relying on it."

} > "$BODY_TMP"

# ---------------------------------------------------------------------------
# Final-pass redaction over the entire assembled body
# ---------------------------------------------------------------------------
REDACTION_COUNT=0
REDACTION_NOTES=()

cp "$BODY_TMP" "$FINAL_TMP"

PATTERN_COUNT=${#SECRET_PATTERNS[@]}
idx=0
while [ "$idx" -lt "$PATTERN_COUNT" ]; do
  pat="${SECRET_PATTERNS[$idx]}"
  label="${SECRET_LABELS[$idx]}"
  # grep returns exit 1 on no match, which is a legitimate outcome here, not
  # a script error. Guard with || true so pipefail/set -e don't kill the
  # script on a pattern that simply doesn't match.
  GREP_OUT="$(grep -oE "$pat" "$FINAL_TMP" 2>/dev/null || true)"
  if [ -z "$GREP_OUT" ]; then
    HITS=0
  else
    HITS="$(printf '%s\n' "$GREP_OUT" | wc -l | tr -d ' ')"
  fi
  if [ "$HITS" -gt 0 ]; then
    REDACTION_COUNT=$((REDACTION_COUNT + HITS))
    REDACTION_NOTES[${#REDACTION_NOTES[@]}]="Redacted ${HITS} occurrence(s) matching category: ${label}"
    sed -i.bak -E "s/${pat}/[REDACTED]/g" "$FINAL_TMP" 2>/dev/null || \
      sed -i -E "s/${pat}/[REDACTED]/g" "$FINAL_TMP"
    rm -f "${FINAL_TMP}.bak"
  fi
  idx=$((idx + 1))
done

if [ "$REDACTION_COUNT" -gt 0 ]; then
  echo "WARNING: ${REDACTION_COUNT} secret-like pattern(s) detected and redacted. See Redaction Summary in the pack." >&2
fi

# ---------------------------------------------------------------------------
# Append redaction summary + validation summary, write final output
# ---------------------------------------------------------------------------
{
  cat "$FINAL_TMP"
  echo
  echo "---"
  echo
  echo "## Redaction Summary"
  echo
  if [ "$REDACTION_COUNT" -gt 0 ]; then
    echo "- Total redactions: ${REDACTION_COUNT}"
    for note in "${REDACTION_NOTES[@]}"; do
      echo "- ${note}"
    done
  else
    echo "- No secret-like patterns detected."
  fi
  echo
  echo "## Validation Summary"
  echo
  echo "- output_generated: yes"
  echo "- current_HEAD_included: yes (${HEAD_SHA})"
  if [ "${#COMMITS[@]}" -gt 0 ]; then
    echo "- commit_list_validated: yes (${#COMMITS[@]} commit(s))"
  else
    echo "- commit_list_validated: n/a - none supplied"
  fi
  echo "- AGENTS.md_included: yes"
  echo "- CODEX_STATUS.md_included: yes"
  echo "- matching_docs_count: ${DOC_MATCH_COUNT}"
  echo "- grep_sections_count: ${GREP_SECTION_COUNT}"
  echo "- redaction_count: ${REDACTION_COUNT}"
  if [ -n "$DIRTY_WARNING" ]; then
    echo "- warnings_count: 1"
    echo "  - ${DIRTY_WARNING}"
  else
    echo "- warnings_count: 0"
  fi
  echo
  echo "> This pack is a point-in-time snapshot. If repo files change after generation, regenerate before relying on it."
} > "$OUTFILE"

if [ ! -s "$OUTFILE" ]; then
  echo "ERROR: output file was not written or is empty: $OUTFILE" >&2
  exit 1
fi

echo "Pack written to: ${OUTFILE}"
