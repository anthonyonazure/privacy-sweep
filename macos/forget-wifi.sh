#!/usr/bin/env bash
# forget-wifi.sh - part of privacy-sweep (macOS)
# Forgets preferred Wi-Fi networks via networksetup.
# The network you are joined to is kept unless you pass --include-current.
# Removing a network can ask for an administrator password.
#
#   ./forget-wifi.sh --dry-run
#   ./forget-wifi.sh
#   ./forget-wifi.sh --yes
#   ./forget-wifi.sh --yes --include-current
set -euo pipefail

DRY_RUN=false
ASSUME_YES=false
INCLUDE_CURRENT=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes|-y) ASSUME_YES=true ;;
    --include-current) INCLUDE_CURRENT=true ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS. Detected: $(uname -s)." >&2
  exit 1
fi

confirm() {
  if [[ "$ASSUME_YES" == true ]]; then
    return 0
  fi
  local answer
  read -r -p "Forget the saved Wi-Fi networks listed above? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

DEVICE=""
# networksetup prints the device on the line after the Wi-Fi hardware port.
while IFS= read -r line; do
  if [[ "$line" == *"Device:"* && -n "${WANT_DEV:-}" ]]; then
    DEVICE="${line#Device: }"
    DEVICE="${DEVICE#"${DEVICE%%[![:space:]]*}"}"
    break
  fi
  if [[ "$line" == *"Wi-Fi"* || "$line" == *"AirPort"* ]]; then
    WANT_DEV=1
  else
    WANT_DEV=""
  fi
done < <(networksetup -listallhardwareports)

if [[ -z "$DEVICE" ]]; then
  echo "Could not find a Wi-Fi device via networksetup -listallhardwareports." >&2
  exit 1
fi

CURRENT=""
AIR="$(networksetup -getairportnetwork "$DEVICE" 2>/dev/null || true)"
if [[ "$AIR" == Current\ Wi-Fi\ Network:\ * ]]; then
  CURRENT="${AIR#Current Wi-Fi Network: }"
fi

echo "== Preferred Wi-Fi networks on $DEVICE =="
if [[ -n "$CURRENT" ]]; then
  echo "Joined now: $CURRENT"
else
  echo "Not joined to a Wi-Fi network."
fi

DROP=()
while IFS= read -r line; do
  name="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$name" || "$name" == Preferred\ networks* ]] && continue
  if [[ -n "$CURRENT" && "$name" == "$CURRENT" && "$INCLUDE_CURRENT" != true ]]; then
    echo "In use, will keep: $name"
    continue
  fi
  DROP+=("$name")
  if [[ -n "$CURRENT" && "$name" == "$CURRENT" ]]; then
    echo "Would forget (this disconnects you): $name"
  else
    echo "Would forget: $name"
  fi
done < <(networksetup -listpreferredwirelessnetworks "$DEVICE")

if [[ ${#DROP[@]} -eq 0 ]]; then
  echo "Nothing to forget."
  exit 0
fi
if [[ -n "$CURRENT" && "$INCLUDE_CURRENT" != true ]]; then
  echo "Pass --include-current to forget the network this Mac is using."
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry run) Would remove ${#DROP[@]} preferred network(s). No change made."
  exit 0
fi
confirm || { echo "Cancelled."; exit 0; }

for name in "${DROP[@]}"; do
  networksetup -removepreferredwirelessnetwork "$DEVICE" "$name"
  echo "Forgot: $name"
done
echo "Done."
