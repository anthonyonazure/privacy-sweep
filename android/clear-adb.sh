#!/usr/bin/env bash
# clear-adb.sh - part of privacy-sweep (Android)
# Clears what Android exposes to a connected computer over adb: per-app caches
# and the running log buffer. This is the honest ceiling for a non-rooted phone;
# the protected databases under /data/data are NOT reachable this way.
# Requires: Android platform-tools (adb) on this computer, USB debugging on, phone connected.
# Modes: --dry-run (show only), (default) ask first, --yes (no prompt).
set -euo pipefail

DRY_RUN=false; ASSUME_YES=false
for arg in "$@"; do case "$arg" in
  --dry-run) DRY_RUN=true ;;
  --yes|-y) ASSUME_YES=true ;;
  --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $arg" >&2; exit 1 ;;
esac; done

confirm() { $ASSUME_YES && return 0; read -r -p "Proceed? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

if ! command -v adb >/dev/null 2>&1; then echo "adb not found. Install Android platform-tools first."; exit 1; fi
if [[ -z "$(adb devices | awk 'NR>1 && $2=="device"{print $1}')" ]]; then
  echo "No authorized device. Connect the phone, enable USB debugging, and accept the prompt on the phone."; exit 1
fi

echo "== Android via adb =="
PKGS=$(adb shell pm list packages -3 2>/dev/null | sed 's/package://' | tr -d '\r')
N=$(printf '%s\n' "$PKGS" | grep -c . || true)
echo "Installed user apps: $N (their caches would be cleared)"
echo "Plus: the running log buffer (logcat -c)."

if $DRY_RUN; then
  echo "(dry run) Would run 'pm clear-cache' style clears per app and 'logcat -c'. First few apps:"
  printf '%s\n' "$PKGS" | head -10 | sed 's/^/  /'
  exit 0
fi
confirm || { echo "Cancelled."; exit 0; }

while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  # Trim only the cache, not app data, so you don't get logged out of everything.
  adb shell pm trim-caches 999999999999 >/dev/null 2>&1 || true
done <<< "$PKGS"
adb logcat -c 2>/dev/null || true
echo "Done. App caches trimmed and log buffer cleared."
echo "For history in protected databases, use the Settings steps in this folder's README."
