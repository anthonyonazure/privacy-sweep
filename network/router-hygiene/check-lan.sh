#!/usr/bin/env bash
# check-lan.sh - part of privacy-sweep (router hygiene)
# From a computer on your own LAN, checks a few things the router advertises:
# whether SSDP/UPnP answers, whether a short list of gateway ports is open,
# which DNS resolvers this host is using, and whether a direct query to
# 8.8.8.8 or 1.1.1.1 gets an answer.
#
# It does not log into the router and it does not change any setting.
# The checklist in the README covers the items this script cannot see.
#
#   ./check-lan.sh --dry-run     # read the local route and resolver list only
#   ./check-lan.sh               # show the plan, then ask before probing
#   ./check-lan.sh --yes         # probe without asking
#
# Active mode sends a multicast SSDP search, may run nmap against the
# gateway only, and sends two DNS queries. Use it on a network you administer.
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
MODE="ask"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --ask) MODE="ask" ;;
    --yes|-y) MODE="apply" ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for the LAN checks." >&2
  exit 1
fi

confirm() {
  local answer
  read -r -p "Send the SSDP, port, and DNS probes on this LAN? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

if [[ "$MODE" == "dry-run" ]]; then
  python3 "$LIB/lanprobe.py" passive
  echo "(dry run) No probe was sent."
  exit 0
fi

python3 "$LIB/lanprobe.py" passive
if [[ "$MODE" == "ask" ]]; then
  confirm || { echo "Cancelled. No probe was sent."; exit 0; }
fi

python3 "$LIB/lanprobe.py" active
