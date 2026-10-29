#!/usr/bin/env bash
# audit-usage.sh - Digital Wellbeing / usage-stats presence over adb.
# Report only. Does not print usage-event rows. Does not pm disable.
#
#   ./audit-usage.sh
#   ./audit-usage.sh --dry-run
#   PRIVACY_SWEEP_ADB_FIXTURE=dir ./audit-usage.sh
#
# Not part of clear-all.
set -euo pipefail

SERIAL="${ANDROID_SERIAL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|--yes|-y) ;;
    --serial)
      shift
      [[ $# -gt 0 ]] || { echo "error: --serial needs a device id" >&2; exit 1; }
      SERIAL="$1"
      ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

echo "== Android usage stats (report only) =="
echo "This script does not disable packages and does not print usage events."
echo "Desktop tools cannot replace a mobile acquisition. Settings still holds the history."
echo

FIXTURE="${PRIVACY_SWEEP_ADB_FIXTURE:-}"

adbs() {
  if [[ -n "$FIXTURE" ]]; then
    local key file
    key="$(printf '%s' "$*" | tr ' /' '__')"
    file="$FIXTURE/$key"
    if [[ -f "$file" ]]; then
      cat "$file"
      return 0
    fi
    echo "(no fixture file for: $*)" >&2
    return 1
  fi
  if [[ -n "$SERIAL" ]]; then
    adb -s "$SERIAL" "$@"
  else
    adb "$@"
  fi
}

if [[ -z "$FIXTURE" ]]; then
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb was not found. Install Android platform-tools." >&2
    exit 1
  fi
  devices=()
  while IFS= read -r dev; do
    [[ -n "$dev" ]] && devices+=("$dev")
  done < <(adb devices | awk 'NR>1 && $2=="device" { print $1 }')
  if [[ ${#devices[@]} -eq 0 ]]; then
    echo "No authorized device. Enable USB debugging and accept the prompt." >&2
    exit 1
  fi
  if [[ -z "$SERIAL" && ${#devices[@]} -gt 1 ]]; then
    echo "More than one device is connected. Re-run with --serial and one of:" >&2
    printf '  %s\n' "${devices[@]}" >&2
    exit 1
  fi
  if [[ -z "$SERIAL" ]]; then
    SERIAL="${devices[0]}"
  fi
  echo "Device: $SERIAL"
  echo
fi

packages=""
if ! packages="$(adbs shell pm list packages 2>/dev/null | tr -d '\r')"; then
  echo "(no package list)"
  echo "Done. Nothing was disabled or removed."
  exit 1
fi

listed() {
  local name="$1"
  printf '%s\n' "$packages" | grep -Fqx -- "package:$name"
}

echo "-- Digital Wellbeing and related packages --"
for pkg in com.google.android.apps.wellbeing com.samsung.android.forest com.google.android.apps.turbo; do
  if listed "$pkg"; then
    echo "  present  $pkg"
  else
    echo "  absent   $pkg"
  fi
done
echo

echo "-- dumpsys usagestats (line count only) --"
raw=""
if raw="$(adbs shell dumpsys usagestats 2>/dev/null | tr -d '\r')"; then
  lines="$(printf '%s\n' "$raw" | grep -c . || true)"
  echo "Lines: ${lines:-0}"
  echo "Usage events are not printed."
else
  echo "Lines: unavailable"
fi
echo
echo "Done. Nothing was disabled or removed."
