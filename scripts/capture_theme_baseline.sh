#!/bin/bash
# Captures light/dark before screenshots for the liquid-glass theme work.
# Requires a booted iPhone simulator with Milehound installed.
# Usage: scripts/capture_theme_baseline.sh [light|dark|both]
# Output: /tmp/th-before/{light,dark}/<screen>.png

set -euo pipefail

MODE="${1:-both}"
DEST="/tmp/th-before"
BUNDLE="com.milehound.app"

mkdir -p "$DEST/light" "$DEST/dark"

udid="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone/{print $2; exit}')"
if [[ -z "${udid:-}" ]]; then
  echo "No booted iPhone simulator. Boot one, install Milehound, then re-run."
  exit 1
fi

capture() {
  local appearance="$1"
  xcrun simctl ui "$udid" appearance "$appearance"
  sleep 1
  xcrun simctl io "$udid" screenshot "$DEST/$appearance/home.png"
  echo "Wrote $DEST/$appearance/home.png"
}

case "$MODE" in
  light) capture light ;;
  dark) capture dark ;;
  both) capture light; capture dark ;;
  *) echo "Usage: $0 [light|dark|both]"; exit 1 ;;
esac

echo "Baseline screenshots in $DEST"
echo "Instruments FPS/CPU (trips scroll, Stats, recording card, live follow) must be captured on a physical device — not available in this environment."
