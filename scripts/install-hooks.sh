#!/bin/bash
# Run this once after a fresh clone to install the git pre-commit hook.
# Usage: bash scripts/install-hooks.sh
cp scripts/pre-commit.hook .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo "pre-commit hook installed."
