#!/usr/bin/env bash
# inventory.sh - part of privacy-sweep (LAN)
# Lists devices on the LAN you are joined to. Dry-run reads the ARP table
# only. A full run also does mDNS, SSDP, and (if nmap is installed) nmap -sn
# of this host's IPv4 subnet, then labels addresses from Pi-hole when
# credentials or a database copy are available.
#
#   ./inventory.sh --dry-run          # ARP only, no packets sent
#   ./inventory.sh                    # show the passive list, then ask
#   ./inventory.sh --yes              # probe without asking
#
# Pi-hole names, when you want them:
#   PIHOLE_URL + PIHOLE_PASSWORD, or PIHOLE_FTL_DB=/path/to/pihole-FTL.db
#   --fixture DIR uses tests/fixtures data and does not hit the network for names
#
# TVs are flagged from names and discovery banners (Roku, webOS, Chromecast,
# and similar). A TV on a guest VLAN this computer is not on will not show up.
# Run the script while joined to the network you want to inspect.
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
MODE="ask"
FIXTURE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --ask) MODE="ask" ;;
    --yes|-y) MODE="apply" ;;
    --fixture)
      shift
      [[ $# -gt 0 ]] || { echo "error: --fixture needs a directory" >&2; exit 1; }
      FIXTURE="$1"
      ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for the LAN inventory." >&2
  exit 1
fi

confirm() {
  local answer
  read -r -p "Probe this LAN with mDNS, SSDP, and nmap -sn (if installed)? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

NAMES="$(mktemp)"
trap 'rm -f "$NAMES" "$NAMES.err"' EXIT

name_args=()
if [[ -n "$FIXTURE" ]]; then
  name_args+=(--fixture "$FIXTURE")
fi

if ! python3 "$LIB/pihole.py" "${name_args[@]}" names >"$NAMES" 2>"$NAMES.err"; then
  echo "Pi-hole names were not loaded."
  echo '{}' >"$NAMES"
fi
if [[ -s "$NAMES.err" ]]; then
  sed 's/^/  /' "$NAMES.err"
fi
rm -f "$NAMES.err"

if [[ "$MODE" == "dry-run" ]]; then
  python3 "$LIB/lanprobe.py" inventory --names "$NAMES"
  echo "(dry run) Did not send mDNS, SSDP, or nmap probes."
  exit 0
fi

python3 "$LIB/lanprobe.py" inventory --names "$NAMES"
if [[ "$MODE" == "ask" ]]; then
  confirm || { echo "Cancelled. No probe was sent."; exit 0; }
fi

python3 "$LIB/lanprobe.py" inventory --active --names "$NAMES"
