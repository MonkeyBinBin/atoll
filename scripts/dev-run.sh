#!/usr/bin/env bash
# Rebuild and relaunch the app with the debug hook enabled (ATOLL_DEBUG_DIR required).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ATOLL_DEBUG_DIR:?set ATOLL_DEBUG_DIR}"
pkill -f "Atoll.app/Contents/MacOS/Atoll" || true
./scripts/build-app.sh debug >/dev/null
mkdir -p "$ATOLL_DEBUG_DIR"
nohup "build/Atoll.app/Contents/MacOS/Atoll" > "$ATOLL_DEBUG_DIR/app.log" 2>&1 &
