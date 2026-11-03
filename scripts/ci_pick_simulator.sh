#!/usr/bin/env bash
# Prints a xcodebuild -destination value for an available iPhone simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

preferred=("iPhone 17" "iPhone 16" "iPhone 16 Pro" "iPhone 15" "iPhone SE (3rd generation)")
uuid_re='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'

pick_from_simctl() {
  local devices
  devices="$(xcrun simctl list devices available)"
  local name id
  for name in "${preferred[@]}"; do
    id="$(printf '%s\n' "$devices" | grep -F "    ${name} (" | head -1 | grep -oE "$uuid_re" || true)"
    if [[ -n "$id" ]]; then
      echo "platform=iOS Simulator,id=${id}"
      return 0
    fi
  done
  return 1
}

# `name:iPhone 17 }` — not a prefix of `name:iPhone 17 Pro` or `name:iPhone 17e`.
destination_display_name() {
  local line="$1" name
  name="$(printf '%s\n' "$line" | sed -n 's/.*name:[[:space:]]*\(.*\)[[:space:]]*}.*/\1/p')"
  name="${name%"${name##*[![:space:]]}"}"
  printf '%s' "$name"
}

destination_os_version() {
  printf '%s\n' "$1" | sed -n 's/.*OS:\([0-9][0-9.]*\).*/\1/p'
}

# Newer runtime wins so a leftover iOS 26.2 device is not chosen over 26.5.
os_version_is_newer() {
  local candidate="$1" current="$2"
  [[ -z "$current" ]] && return 0
  [[ "$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -1)" == "$candidate" && "$candidate" != "$current" ]]
}

pick_from_xcodebuild() {
  local destinations_file line pick_line id name os
  destinations_file="$(mktemp)"
  xcodebuild -showdestinations -project Milehound.xcodeproj -scheme Milehound 2>/dev/null \
    | grep -E "platform: ?iOS Simulator" \
    | grep -vi placeholder \
    | grep -E "name: ?iPhone" > "$destinations_file" || true

  if [[ ! -s "$destinations_file" ]]; then
    rm -f "$destinations_file"
    return 1
  fi

  # Walk preferred names first. A line-first scan treats `iPhone 16e` as `iPhone 16`
  # and stops before `iPhone 17`, which is what sent CI to iOS 26.2.
  pick_line=""
  for name in "${preferred[@]}"; do
    local best_line="" best_os="" saw_baseline=0
    while IFS= read -r line; do
      [[ "$(destination_display_name "$line")" == "$name" ]] || continue
      os="$(destination_os_version "$line")"
      # Snapshots and run_tests.sh pin iOS 26.5. Prefer that runtime over a
      # newer beta or an older leftover such as iOS 26.2.
      if [[ "$os" == "26.5" ]]; then
        best_line="$line"
        best_os="$os"
        saw_baseline=1
        break
      fi
      if [[ "$saw_baseline" == "0" ]] && os_version_is_newer "$os" "$best_os"; then
        best_line="$line"
        best_os="$os"
      fi
    done < "$destinations_file"
    if [[ -n "$best_line" ]]; then
      pick_line="$best_line"
      break
    fi
  done

  if [[ -z "$pick_line" ]]; then
    pick_line="$(head -1 "$destinations_file")"
  fi
  rm -f "$destinations_file"

  id="$(echo "$pick_line" | grep -oE "id:${uuid_re}" | head -1 | cut -d: -f2)"
  if [[ -z "$id" ]]; then
    return 1
  fi

  echo "platform=iOS Simulator,id=${id}"
}

pick_fallback_name_os() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    # GitHub macos-26 ships iPhone 17 + iOS 26.x with Xcode 26.
    echo "platform=iOS Simulator,name=iPhone 17,OS=26.5"
  else
    echo "platform=iOS Simulator,name=iPhone 16,OS=18.5"
  fi
}

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  if pick_from_xcodebuild; then exit 0; fi
  if pick_from_simctl; then exit 0; fi
  pick_fallback_name_os
  exit 0
fi

if pick_from_simctl; then exit 0; fi
if pick_from_xcodebuild; then exit 0; fi
pick_fallback_name_os
