#!/usr/bin/env bash
# add-blocklists.sh - part of privacy-sweep (Pi-hole)
# Adds maintained smart-TV / ACR blocklists to a Pi-hole you administer.
# Dry-run is the default. Nothing is added until you pass --ask or --yes.
#
#   ./add-blocklists.sh                 # show the lists, change nothing
#   ./add-blocklists.sh --dry-run       # same as the default
#   ./add-blocklists.sh --ask           # show the lists, then ask
#   ./add-blocklists.sh --yes           # add them and update gravity
#   ./add-blocklists.sh --yes --brand samsung,lg
#
# Optional:
#   --brand LIST        comma-separated brand ids (repeatable):
#                       samsung, lg, roku, firetv, vizio, hisense
#                       Adds that brand's HaGeZi list when one exists.
#                       Vizio and Hisense have no native list.
#   --vendor            samsung, lg, roku, and firetv. Ignored if --brand is set.
#   --adguard           talk to AdGuard Home (ADGUARD_URL) instead of Pi-hole
#   --pihole            talk to Pi-hole (the default)
#   --alphonso-regex    also add a regex for Alphonso (alphonso.tv)
#   --no-gravity        do not ask the resolver to reload
#   --fixture DIR       read JSON stand-ins instead of a live resolver
#   --apply-log PATH    with --fixture --yes, record the intended change
#
# Keep-list rows in keep.txt are allowlisted on every apply. Watch rows are
# printed and not written.
#
# Environment (do not put the password on the command line):
#   PIHOLE_URL              default http://pi.hole
#   PIHOLE_PASSWORD         v6 admin or application password
#   PIHOLE_PASSWORD_FILE    a file whose contents are that password
#   PIHOLE_GRAVITY_DB       v5 only: a gravity.db on this machine
#   PIHOLE_INSECURE=1       skip TLS verification for a self-signed cert
#   ADGUARD_URL             origin, for example http://192.168.1.3:3000
#   ADGUARD_USER            default admin
#   ADGUARD_PASSWORD        or ADGUARD_PASSWORD_FILE
#   ADGUARD_INSECURE=1      skip TLS verification for a self-signed cert
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
    --brand)
      shift
      [[ $# -gt 0 ]] || { echo "error: --brand needs a list such as samsung,lg" >&2; exit 1; }
      PY_ARGS+=(--brand "$1")
      ;;
    --adguard) PY_ARGS+=(--resolver adguard) ;;
    --pihole) PY_ARGS+=(--resolver pihole) ;;
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
  read -r -p "Apply this plan to the resolver? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

echo "List changes are a dry run unless you pass --ask or --yes."
python3 "$LIB/pihole.py" --lists "$(dirname "${BASH_SOURCE[0]}")/lists.txt" "${PY_ARGS[@]}" plan

if [[ "$MODE" == "dry-run" ]]; then
  exit 0
fi
if [[ "$MODE" == "ask" ]]; then
  confirm || { echo "Cancelled."; exit 0; }
fi

python3 "$LIB/pihole.py" --lists "$(dirname "${BASH_SOURCE[0]}")/lists.txt" "${PY_ARGS[@]}" apply
echo "Done."
