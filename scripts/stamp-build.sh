#!/bin/bash
# Updates BUILD_TS in index.html to current local time.
# Run before every commit: bash scripts/stamp-build.sh
set -e
TS=$(date +"%Y-%m-%dT%H:%M:%S")
sed -i '' "s|const BUILD_TS='[^']*'|const BUILD_TS='$TS'|" index.html
echo "BUILD_TS updated to $TS"
