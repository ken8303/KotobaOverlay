#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-run}"
case "$mode" in run|--debug|--logs|--telemetry|--verify) ;; *) echo 'Usage: build_and_run.sh [--debug|--logs|--telemetry|--verify]' >&2; exit 2;; esac
# Export any in-memory subtitles before using this developer restart command.
pkill -x KotobaOverlay >/dev/null 2>&1 || true
xcodebuild -project KotobaOverlay.xcodeproj -scheme KotobaOverlay -configuration Debug -derivedDataPath DerivedData build
app="$PWD/DerivedData/Build/Products/Debug/KotobaOverlay.app"
if [[ "$mode" == --debug ]]; then
    exec lldb -- "$app/Contents/MacOS/KotobaOverlay"
fi
open -n "$app"
case "$mode" in
    --logs|--telemetry) exec /usr/bin/log stream --info --style compact --predicate 'process == "KotobaOverlay"';;
    --verify) sleep 1; pgrep -x KotobaOverlay >/dev/null;;
esac
