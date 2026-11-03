#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
# Optional second pass for the iPad tab rail and wide panes. iPhone runs skip those UI tests.
# PAD_DESTINATION="platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5" ./scripts/run_tests.sh
PAD_DESTINATION="${PAD_DESTINATION:-}"
RESULT_BUNDLE="${RESULT_BUNDLE:-build/TestResults.xcresult}"
INCLUDE_UI_TESTS="${INCLUDE_UI_TESTS:-1}"
ONLY_UI_TESTS="${ONLY_UI_TESTS:-0}"
# test | build-for-testing | test-without-building
XCODEBUILD_ACTION="${XCODEBUILD_ACTION:-test}"
SOURCE_PACKAGES_DIR="${SOURCE_PACKAGES_DIR:-}"

case "$XCODEBUILD_ACTION" in
  test|build-for-testing|test-without-building) ;;
  *)
    echo "Unknown XCODEBUILD_ACTION: $XCODEBUILD_ACTION" >&2
    exit 64
    ;;
esac

mkdir -p build
rm -rf "$RESULT_BUNDLE"

TEST_ARGS=()
if [[ "$XCODEBUILD_ACTION" == "build-for-testing" ]]; then
  :
elif [[ "$ONLY_UI_TESTS" == "1" ]]; then
  TEST_ARGS+=(-only-testing:MilehoundUITests)
elif [[ "$INCLUDE_UI_TESTS" == "0" ]]; then
  TEST_ARGS+=(-only-testing:MilehoundTests)
fi

XCODEBUILD_SETTINGS=()
if [[ "${CI:-}" == "true" ]]; then
  XCODEBUILD_SETTINGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )
fi

RETRY_ARGS=()
if [[ "${CI:-}" == "true" && "$XCODEBUILD_ACTION" != "build-for-testing" ]]; then
  RETRY_ARGS+=(-retry-tests-on-failure)
fi

boot_simulator_if_needed() {
  local sim_id=""
  if [[ "$DESTINATION" == *"id="* ]]; then
    sim_id="${DESTINATION##*id=}"
  fi
  if [[ -n "$sim_id" ]]; then
    echo "Booting simulator ${sim_id}"
    xcrun simctl boot "$sim_id" 2>/dev/null || true
    # Repeating SwiftUI animations keep XCTest from reaching quiescence on iOS 26.
    xcrun simctl spawn "$sim_id" defaults write com.apple.Accessibility ReduceMotionEnabled -int 1 2>/dev/null || true
  fi
}

print_failure_summary() {
  [[ -d "$RESULT_BUNDLE" ]] || return 0
  if ! command -v xcrun >/dev/null 2>&1; then
    return 0
  fi

  echo ""
  echo "=== Test failure summary ==="
  xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" 2>/dev/null || true

  echo ""
  echo "=== Failed tests ==="
  xcrun xcresulttool get test-results tests --path "$RESULT_BUNDLE" 2>/dev/null \
    | python3 - <<'PY' 2>/dev/null || true
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

def walk(node):
    if isinstance(node, dict):
        status = node.get("testStatus", {})
        if status.get("status") == "Failure":
            name = node.get("name") or node.get("identifier")
            if name:
                print(name)
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for item in node:
            walk(item)

walk(data)
PY
}

if [[ "$XCODEBUILD_ACTION" != "build-for-testing" ]]; then
  boot_simulator_if_needed
fi

# Bash 3.2 + `set -u` treats empty "${arr[@]}" as unbound; build one argv list instead.
XCODEBUILD_ARGV=(
  "$XCODEBUILD_ACTION"
  -project Milehound.xcodeproj
  -scheme Milehound
  -destination "$DESTINATION"
  -resultBundlePath "$RESULT_BUNDLE"
)
if [[ "$XCODEBUILD_ACTION" != "build-for-testing" ]]; then
  XCODEBUILD_ARGV+=(-parallel-testing-enabled NO)
fi
if [[ -n "$SOURCE_PACKAGES_DIR" ]]; then
  XCODEBUILD_ARGV+=(-clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR")
fi
if ((${#RETRY_ARGS[@]})); then
  XCODEBUILD_ARGV+=("${RETRY_ARGS[@]}")
fi
if ((${#XCODEBUILD_SETTINGS[@]})); then
  XCODEBUILD_ARGV+=("${XCODEBUILD_SETTINGS[@]}")
fi
if ((${#TEST_ARGS[@]})); then
  XCODEBUILD_ARGV+=("${TEST_ARGS[@]}")
fi

set +e
xcodebuild "${XCODEBUILD_ARGV[@]}"
STATUS=$?
set -e

if [[ "$STATUS" -ne 0 ]]; then
  echo "xcodebuild $XCODEBUILD_ACTION failed with status $STATUS"
  echo "Result bundle: $RESULT_BUNDLE"
  print_failure_summary
  exit "$STATUS"
fi

if [[ "$XCODEBUILD_ACTION" == "build-for-testing" ]]; then
  echo "Build for testing succeeded."
else
  echo "All tests passed."
fi

if [[ -n "$PAD_DESTINATION" && "$XCODEBUILD_ACTION" != "build-for-testing" ]]; then
  PAD_BUNDLE="${RESULT_BUNDLE%.xcresult}-ipad.xcresult"
  rm -rf "$PAD_BUNDLE"
  echo "Running iPad destination: $PAD_DESTINATION"
  PAD_ARGV=("${XCODEBUILD_ARGV[@]}")
  for i in "${!PAD_ARGV[@]}"; do
    if [[ "${PAD_ARGV[$i]}" == "-destination" ]]; then
      PAD_ARGV[$((i + 1))]="$PAD_DESTINATION"
    fi
    if [[ "${PAD_ARGV[$i]}" == "-resultBundlePath" ]]; then
      PAD_ARGV[$((i + 1))]="$PAD_BUNDLE"
    fi
  done
  set +e
  xcodebuild "${PAD_ARGV[@]}"
  PAD_STATUS=$?
  set -e
  if [[ "$PAD_STATUS" -ne 0 ]]; then
    echo "iPad xcodebuild failed with status $PAD_STATUS"
    echo "Result bundle: $PAD_BUNDLE"
    RESULT_BUNDLE="$PAD_BUNDLE"
    print_failure_summary
    exit "$PAD_STATUS"
  fi
  echo "iPad tests passed."
fi
