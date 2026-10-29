#!/usr/bin/env bash
# audit-permissions.sh - part of privacy-sweep (Android, report only)
# Over adb, lists apps that can see or interrupt a lot of what you do:
# accessibility services, device admin, SMS and call-log access, notification
# listeners, and the overlay ("draw over other apps") permission.
# Third-party apps whose installer is not the Play Store are flagged.
# Nothing is uninstalled, disabled, or revoked.
#
#   ./audit-permissions.sh
#   ./audit-permissions.sh --dry-run     # same report; there is nothing to apply
#   ./audit-permissions.sh --yes         # same report
#   ./audit-permissions.sh --serial SERIAL
#
# Requires USB debugging and an authorized adb connection.
# PRIVACY_SWEEP_ADB_FIXTURE=dir reads captured command output instead of a phone,
# so the parser can be tried with no device. That variable is a test aid.
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

echo "== Android sensitive permissions (report only) =="
echo "This script does not uninstall apps or change permissions."
echo

FIXTURE="${PRIVACY_SWEEP_ADB_FIXTURE:-}"

adbs() {
  if [[ -n "$FIXTURE" ]]; then
    local key
    key="$(printf '%s' "$*" | tr ' /' '__')"
    local file="$FIXTURE/$key"
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
    echo "adb was not found. Install Android platform-tools and connect the phone." >&2
    exit 1
  fi
  mapfile -t DEVICES < <(adb devices | awk 'NR>1 && $2=="device" { print $1 }')
  if [[ ${#DEVICES[@]} -eq 0 ]]; then
    echo "No authorized device. Enable USB debugging and accept the prompt on the phone." >&2
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

section() {
  echo "-- $1 --"
  if ! adbs shell "${@:2}" 2>/dev/null | tr -d '\r'; then
    echo "(the phone did not answer this query)"
  fi
  echo
}

section "Accessibility services" settings get secure enabled_accessibility_services
section "Notification listeners" settings get secure enabled_notification_listeners

echo "-- Device admin --"
admin_out="$(adbs shell dumpsys device_policy 2>/dev/null | tr -d '\r' || true)"
if [[ -z "$admin_out" ]]; then
  echo "(could not read device_policy; the phone may be denying dumpsys)"
else
  printf '%s\n' "$admin_out" | grep -E -i 'admin|DeviceAdmin|mAdminMap' | head -n 40 || echo "(no admin lines in device_policy)"
fi
echo

echo "-- SMS, call log, and overlay (appops) --"
for op in READ_SMS RECEIVE_SMS READ_CALL_LOG WRITE_CALL_LOG PROCESS_OUTGOING_CALLS SYSTEM_ALERT_WINDOW; do
  echo "  $op:"
  if ! adbs shell cmd appops query-op "$op" allow 2>/dev/null | tr -d '\r' | sed 's/^/    /'; then
    echo "    (appops query failed; Android 8 or newer is required for cmd appops)"
  fi
done
echo

echo "-- Third-party apps and installers --"
echo "Play Store installer: com.android.vending"
echo "Anything else is flagged. An OEM store (Galaxy Store, and similar) is not a"
echo "random sideload, but it is also not Play, so it is listed with its installer."
echo
if ! adbs shell pm list packages -i -3 2>/dev/null | tr -d '\r' | while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pkg="${line%% *}"
  pkg="${pkg#package:}"
  installer="unknown"
  if [[ "$line" == *"installer="* ]]; then
    installer="${line#*installer=}"
    installer="${installer%% *}"
  fi
  if [[ "$installer" == "com.android.vending" ]]; then
    printf '  play    %s\n' "$pkg"
  elif [[ -z "$installer" || "$installer" == "null" ]]; then
    printf '  FLAG    %s    installer=none (sideload, adb, or a preloaded user app)\n' "$pkg"
  else
    printf '  FLAG    %s    installer=%s (not Play)\n' "$pkg" "$installer"
  fi
done; then
  echo "(could not list packages)"
fi

echo
echo "Done. No packages were removed or changed."
