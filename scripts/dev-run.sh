#!/usr/bin/env bash
# Rebuild and relaunch the app with the debug hook enabled (HERDR_ISLAND_DEBUG_DIR required).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${HERDR_ISLAND_DEBUG_DIR:?set HERDR_ISLAND_DEBUG_DIR}"
pkill -f "Herdr Island.app/Contents/MacOS/HerdrIsland" || true
./scripts/build-app.sh debug >/dev/null
mkdir -p "$HERDR_ISLAND_DEBUG_DIR"
nohup "build/Herdr Island.app/Contents/MacOS/HerdrIsland" > "$HERDR_ISLAND_DEBUG_DIR/app.log" 2>&1 &
