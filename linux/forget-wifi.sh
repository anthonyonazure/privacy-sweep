#!/usr/bin/env bash
# forget-wifi.sh - part of privacy-sweep (Linux)
# Forgets saved Wi-Fi networks known to NetworkManager (nmcli).
# The network you are using right now is kept unless you pass --include-current.
#
#   ./forget-wifi.sh --dry-run
#   ./forget-wifi.sh                 # list, then ask
#   ./forget-wifi.sh --yes
#   ./forget-wifi.sh --yes --include-current
#
# Wired connections are never deleted.
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

confirm() {
  if [[ "$ASSUME_YES" == true ]]; then
    return 0
  fi
  local answer
  read -r -p "Forget the saved Wi-Fi networks listed above? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

if ! command -v nmcli >/dev/null 2>&1; then
  echo "nmcli was not found. This script talks to NetworkManager." >&2
  echo "If Wi-Fi on this machine is handled by something else, forget the network there." >&2
  exit 1
fi

# nmcli -t escapes colons inside fields as '\:'.
split_nmcli() {
  local line="$1" part="" esc=0 i c
  NM_FIELDS=()
  for ((i = 0; i < ${#line}; i++)); do
    c="${line:i:1}"
    if [[ "$esc" -eq 1 ]]; then
      part+="$c"
      esc=0
      continue
    fi
    if [[ "$c" == "\\" ]]; then
      esc=1
      continue
    fi
    if [[ "$c" == ':' ]]; then
      NM_FIELDS+=("$part")
      part=""
      continue
    fi
    part+="$c"
  done
  NM_FIELDS+=("$part")
}

declare -A ACTIVE=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  split_nmcli "$line"
  [[ -n "${NM_FIELDS[0]:-}" ]] && ACTIVE["${NM_FIELDS[0]}"]=1
done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active)

echo "== Saved Wi-Fi networks (NetworkManager) =="
DROP=()
KEEP=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  split_nmcli "$line"
  name="${NM_FIELDS[0]:-}"
  kind="${NM_FIELDS[1]:-}"
  dev="${NM_FIELDS[2]:-}"
  [[ "$kind" == "802-11-wireless" ]] || continue
  if [[ -n "${ACTIVE[$name]:-}" && "$INCLUDE_CURRENT" != true ]]; then
    KEEP+=("$name")
    echo "In use, will keep: $name (device ${dev:-none})"
  else
    DROP+=("$name")
    if [[ -n "${ACTIVE[$name]:-}" ]]; then
      echo "Would forget (this disconnects you): $name"
    else
      echo "Would forget: $name"
    fi
  fi
done < <(nmcli -t -f NAME,TYPE,DEVICE connection show)

if [[ ${#DROP[@]} -eq 0 && ${#KEEP[@]} -eq 0 ]]; then
  echo "No saved Wi-Fi profiles found."
  exit 0
fi
if [[ ${#KEEP[@]} -gt 0 && "$INCLUDE_CURRENT" != true ]]; then
  echo "Pass --include-current to forget the network this computer is using."
fi
if [[ ${#DROP[@]} -eq 0 ]]; then
  echo "Nothing to forget."
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry run) Would delete ${#DROP[@]} Wi-Fi profile(s). No change made."
  exit 0
fi
confirm || { echo "Cancelled."; exit 0; }

for name in "${DROP[@]}"; do
  nmcli connection delete id "$name"
  echo "Forgot: $name"
done
echo "Done."
