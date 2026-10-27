#!/usr/bin/env bash
# add-blocklists.sh - part of privacy-sweep (Pi-hole)
# Adds maintained smart-TV / ACR blocklists to a Pi-hole you administer.
# Dry-run is the default. Nothing is added until you pass --ask or --yes.
#
#   ./add-blocklists.sh                 # show the lists, change nothing
#   ./add-blocklists.sh --dry-run       # same as the default
#   ./add-blocklists.sh --ask           # show the lists, then ask
#   ./add-blocklists.sh --yes           # add them and update gravity
#
# Optional:
#   --vendor            also add the wider per-vendor lists in lists.txt
#   --alphonso-regex    also add a regex for Alphonso (alphonso.tv)
#   --no-gravity        do not ask Pi-hole to rebuild gravity
#   --fixture DIR       read JSON stand-ins instead of a live Pi-hole
#   --apply-log PATH    with --fixture --yes, record the intended change
#
# Environment (do not put the password on the command line):
#   PIHOLE_URL              default http://pi.hole
#   PIHOLE_PASSWORD         v6 admin or application password
#   PIHOLE_PASSWORD_FILE    a file whose contents are that password
#   PIHOLE_GRAVITY_DB       v5 only: a gravity.db on this machine
#   PIHOLE_INSECURE=1       skip TLS verification for a self-signed cert
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
MODE="dry-run"
PY_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --ask) MODE="ask" ;;
    --yes|-y) MODE="apply" ;;
    --vendor) PY_ARGS+=(--vendor) ;;
    --alphonso-regex) PY_ARGS+=(--alphonso-regex) ;;
    --no-gravity) PY_ARGS+=(--no-gravity) ;;
    --fixture)
      shift
      [[ $# -gt 0 ]] || { echo "error: --fixture needs a directory" >&2; exit 1; }
      PY_ARGS+=(--fixture "$1")
      ;;
    --apply-log)
      shift
      [[ $# -gt 0 ]] || { echo "error: --apply-log needs a path" >&2; exit 1; }
      PY_ARGS+=(--apply-log "$1")
      ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for the Pi-hole scripts." >&2
  exit 1
fi

confirm() {
  local answer
  read -r -p "Add these lists to Pi-hole? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

echo "Pi-hole list changes are a dry run unless you pass --ask or --yes."
python3 "$LIB/pihole.py" --lists "$(dirname "${BASH_SOURCE[0]}")/lists.txt" "${PY_ARGS[@]}" plan

if [[ "$MODE" == "dry-run" ]]; then
  exit 0
fi
if [[ "$MODE" == "ask" ]]; then
  confirm || { echo "Cancelled."; exit 0; }
fi

python3 "$LIB/pihole.py" --lists "$(dirname "${BASH_SOURCE[0]}")/lists.txt" "${PY_ARGS[@]}" apply
echo "Done."
