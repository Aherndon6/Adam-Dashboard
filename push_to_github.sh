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

# ── 2. Run regression tests ───────────────────────────────────────────────────
echo "Running regression suite..."
node test_regression.js
if [ $? -ne 0 ]; then
  echo "ERROR: Regression tests failed. Push aborted."
  exit 1
fi
echo "Regression suite passed."

# ── 3. Run Playwright e2e tests ───────────────────────────────────────────────
echo "Running Playwright e2e suite..."
node e2e.js
if [ $? -ne 0 ]; then
  echo "ERROR: Playwright e2e tests failed. Push aborted."
  exit 1
fi
echo "Playwright e2e suite passed."

# ── 4. Stamp build timestamp ─────────────────────────────────────────────────
BUILD_TIME=$(date '+%Y-%m-%dT%H:%M:%S')
sed -i '' "s/const BUILD_TS='[^']*'/const BUILD_TS='${BUILD_TIME}'/" index.html
echo "Build timestamp updated: ${BUILD_TIME}"

# ── 5. Stage, commit, push ────────────────────────────────────────────────────
git add -A   # stage everything — BUILD_TS already stamped above
git status --short

git commit -m "$COMMIT_MSG"
git push

echo ""
echo "Done! Pushed: $COMMIT_MSG"
