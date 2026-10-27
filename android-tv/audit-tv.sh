#!/usr/bin/env bash
# audit-tv.sh - part of privacy-sweep (Android TV / Google TV, report only)
# Over network adb, lists installed packages and which of them are enabled,
# then flags known manufacturer telemetry, ad, and content-row packages.
# Nothing is disabled, hidden, or uninstalled.
#
#   ./audit-tv.sh --host 192.168.1.40
#   ./audit-tv.sh --host 192.168.1.40:5555
#   ./audit-tv.sh --serial 192.168.1.40:5555
#   ./audit-tv.sh --dry-run --host 192.168.1.40
#
# --host runs `adb connect`. The TV must already have network debugging on
# (port 5555, or host:port if you pass a port). Accept the prompt on the TV
# the first time.
#
# Reversible disabling of packages, and the replacement launcher, are
# CleanYourTV's, not this script's:
#   https://github.com/Gathin23/cleanyourtv
# Non-Android sets are settings and DNS, not adb:
#   https://cleanyour.tv/not-android
#
# PRIVACY_SWEEP_ADB_FIXTURE=dir reads captured command output instead of a TV.
# That variable is a test aid. Not part of clear-all or privacy-sweep.sh.
set -euo pipefail

SERIAL="${ANDROID_SERIAL:-}"
HOST=""
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOGUE="$ROOT/packages.txt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|--yes|-y) ;;
    --host)
      shift
      [[ $# -gt 0 ]] || { echo "error: --host needs a TV address" >&2; exit 1; }
      HOST="$1"
      ;;
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

if [[ -n "$HOST" && -n "$SERIAL" && "$SERIAL" != "${ANDROID_SERIAL:-}" ]]; then
  echo "error: pass --host or --serial, not both" >&2
  exit 1
fi

echo "== Android TV packages (report only) =="
echo "This script does not disable, uninstall, or hide packages."
echo "For a reversible debloat and a replacement launcher, see CleanYourTV:"
echo "  https://github.com/Gathin23/cleanyourtv"
echo "Samsung, LG, Roku, Vizio, VIDAA, and Fire TV settings are not adb."
echo "  https://cleanyour.tv/not-android"
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
  if [[ -n "$HOST" ]]; then
    if [[ ! "$HOST" =~ ^[A-Za-z0-9._:-]+$ ]]; then
      echo "error: --host may only contain a hostname, an address, and an optional port" >&2
      exit 1
    fi
    if [[ "$HOST" != *:* ]]; then
      HOST="${HOST}:5555"
    fi
    echo "Connecting to $HOST"
    adb connect "$HOST"
    SERIAL="$HOST"
    echo
  fi
  mapfile -t DEVICES < <(adb devices | awk 'NR>1 && $2=="device" { print $1 }')
  if [[ ${#DEVICES[@]} -eq 0 ]]; then
    echo "No authorized device. On the TV, turn on network debugging and accept the prompt." >&2
    exit 1
  fi
  if [[ -z "$SERIAL" && ${#DEVICES[@]} -gt 1 ]]; then
    echo "More than one device is connected. Re-run with --serial and one of:" >&2
    printf '  %s\n' "${DEVICES[@]}" >&2
    exit 1
  fi
  if [[ -z "$SERIAL" ]]; then
    SERIAL="${DEVICES[0]}"
  fi
  echo "Device: $SERIAL"
  echo
fi

if [[ ! -f "$CATALOGUE" ]]; then
  echo "error: missing $CATALOGUE" >&2
  exit 1
fi

read_packages() {
  local label="$1"
  shift
  local raw=""
  if ! raw="$(adbs "$@" 2>/dev/null | tr -d '\r')"; then
    echo "(the TV did not answer: $label)" >&2
    return 1
  fi
  printf '%s\n' "$raw" | sed -n 's/^package://p'
}

listed() {
  local name="$1"
  local list="$2"
  [[ -n "$list" ]] && printf '%s\n' "$list" | grep -Fqx -- "$name"
}

echo "-- Installed packages --"
installed=""
enabled=""
enabled_known=0
if ! installed="$(read_packages "pm list packages" shell pm list packages)"; then
  echo "(no package list; the connection may have failed)"
  echo
  echo "Done. No packages were disabled or removed."
  exit 1
fi
if enabled="$(read_packages "pm list packages -e" shell pm list packages -e)"; then
  enabled_known=1
else
  echo "Enabled-package query failed. Flagged names are listed as installed, without an enabled/disabled split."
  enabled=""
fi

installed_count="$(printf '%s\n' "$installed" | grep -c . || true)"
enabled_count="$(printf '%s\n' "$enabled" | grep -c . || true)"
echo "Installed: $installed_count"
if [[ "$enabled_known" -eq 1 ]]; then
  echo "Enabled:   $enabled_count"
else
  echo "Enabled:   unknown"
fi
echo

section() {
  local title="$1"
  local want="$2"
  local state="$3"
  local found=0 line category package note on
  echo "-- $title --"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    IFS='|' read -r category package note <<< "$line"
    [[ "$category" == "$want" ]] || continue
    if [[ ! "$package" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$ ]]; then
      echo "error: bad package name in catalogue: $package" >&2
      exit 1
    fi
    listed "$package" "$installed" || continue
    on=0
    if [[ "$enabled_known" -eq 1 ]] && listed "$package" "$enabled"; then
      on=1
    fi
    if [[ "$enabled_known" -eq 1 && "$state" == "enabled" && "$on" -eq 0 ]]; then
      continue
    fi
    if [[ "$enabled_known" -eq 1 && "$state" == "disabled" && "$on" -eq 1 ]]; then
      continue
    fi
    if [[ "$enabled_known" -eq 0 ]]; then
      printf '  FLAG  %s  (enabled state unknown)\n' "$package"
    elif [[ "$on" -eq 1 ]]; then
      printf '  FLAG  %s\n' "$package"
    else
      printf '  off   %s\n' "$package"
    fi
    printf '        %s\n' "$note"
    found=1
  done < "$CATALOGUE"
  if [[ "$found" -eq 0 ]]; then
    echo "  (none)"
  fi
  echo
}

section "Telemetry and viewing-data clients, enabled" telemetry enabled
section "Ad packages, enabled" ads enabled
section "Content-row packages, enabled" content-row enabled
if [[ "$enabled_known" -eq 1 ]]; then
  section "Flagged telemetry already disabled" telemetry disabled
  section "Flagged ad packages already disabled" ads disabled
  section "Flagged content-row packages already disabled" content-row disabled
fi

absent=0
total=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%$'\r'}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  IFS='|' read -r category package note <<< "$line"
  total=$((total + 1))
  if ! listed "$package" "$installed"; then
    absent=$((absent + 1))
  fi
done < "$CATALOGUE"
echo "Catalogue names not installed on this TV: $absent of $total"
echo

echo "-- Digital Wellbeing and usage-stats packages (report only) --"
echo "Presence only. Packages are not disabled. Usage events are not printed."
for pkg in com.google.android.apps.wellbeing com.samsung.android.forest com.google.android.apps.turbo; do
  if listed "$pkg" "$installed"; then
    echo "  present  $pkg"
  else
    echo "  absent   $pkg"
  fi
done
echo

echo "Done. No packages were disabled, hidden, or removed."
