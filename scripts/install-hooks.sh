#!/bin/bash
# Run this once after a fresh clone to install the git hooks.
# Usage: bash scripts/install-hooks.sh
#
# pre-commit : stamps BUILD_TS into index.html and re-stages it.
# pre-push   : runs the static regression suite and blocks a red push.
#              Added 2026-09-12 — push_to_github.sh gates correctly but is an
#              opt-in wrapper, so a plain `git push` skipped it. Three pushes did
#              exactly that (c0a3476, 15b372f, caed4737), leaving e2e red for two
#              months and static red for five weeks with nothing to catch it.
#
# Worktrees share the common git dir, so this installs for every worktree at once.
set -e
HOOK_DIR="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$HOOK_DIR"

cp scripts/pre-commit.hook "$HOOK_DIR/pre-commit"
chmod +x "$HOOK_DIR/pre-commit"
echo "pre-commit hook installed -> $HOOK_DIR/pre-commit"

cp scripts/pre-push.hook "$HOOK_DIR/pre-push"
chmod +x "$HOOK_DIR/pre-push"
echo "pre-push hook installed    -> $HOOK_DIR/pre-push"
