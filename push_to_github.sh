#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# Herndon Financial OS — Push to GitHub
# Usage: bash push_to_github.sh "Your commit message"
# Example: bash push_to_github.sh "Phase 3: scenario preview layer"
# ──────────────────────────────────────────────────────────────────────────────
set -e

COMMIT_MSG="${1:-"Update dashboard"}"

# ── 1. Locate the repo ────────────────────────────────────────────────────────
echo "Looking for Adam-Dashboard repo..."
REPO=$(find ~ -name "Adam-Dashboard" -type d -maxdepth 6 2>/dev/null | head -1)

if [ -z "$REPO" ]; then
  echo "ERROR: Could not find Adam-Dashboard folder."
  echo "Run this to locate it:  find ~ -name 'Adam-Dashboard' -type d"
  exit 1
fi

echo "Found repo: $REPO"
cd "$REPO"

# ── 2. Locate the latest built file from Cowork outputs ───────────────────────
# Search across all Cowork sessions (session IDs change each time) for the
# most recently modified dashboard HTML file.
COWORK_BASE="$HOME/Library/Application Support/Claude/local-agent-mode-sessions"

SRC=$(find "$COWORK_BASE" -name "*.html" -path "*/outputs/*" 2>/dev/null \
  | grep -v "mockup\|spec" \
  | xargs ls -t 2>/dev/null \
  | head -1)

if [ -z "$SRC" ]; then
  echo "ERROR: No HTML file found in Cowork outputs folder."
  echo "Expected folder: $COWORK_OUTPUTS"
  exit 1
fi

echo "Source file: $SRC"

# ── 3. Copy to repo as index.html ─────────────────────────────────────────────
cp "$SRC" index.html
echo "Copied to index.html"

# ── 4. Commit and push ────────────────────────────────────────────────────────
git add index.html
git commit -m "$COMMIT_MSG"
git push

echo ""
echo "Done! Pushed to GitHub: $COMMIT_MSG"
