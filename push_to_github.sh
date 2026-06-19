#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# Herndon Financial OS — Push to GitHub
# Usage: bash push_to_github.sh "Your commit message"
# Example: bash push_to_github.sh "feat: goal sweep delta detection"
# ──────────────────────────────────────────────────────────────────────────────
set -e

COMMIT_MSG="${1:-"Update dashboard"}"

# ── 1. Locate the repo ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "index.html" ]; then
  echo "ERROR: index.html not found in $SCRIPT_DIR"
  exit 1
fi

echo "Repo: $SCRIPT_DIR"

# ── 2. Stage, commit, push ────────────────────────────────────────────────────
git add index.html test_regression.js
git status --short

git commit -m "$COMMIT_MSG"
git push

echo ""
echo "Done! Pushed: $COMMIT_MSG"
