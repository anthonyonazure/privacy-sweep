#!/usr/bin/env bash
# weekly-report.sh - part of privacy-sweep (Pi-hole)
# Writes a markdown privacy report: top clients, top blocked domains,
# clients that were not in the previous run, and ACR / smart-TV lookups.
# Read-only against Pi-hole. The only writes are the report file and the
# local list of client IPs used to spot new ones next time.
#
#   ./weekly-report.sh                       # print, then ask before saving
#   ./weekly-report.sh --dry-run             # print only
#   ./weekly-report.sh --yes --output FILE   # save without asking
#
#   --days N        window length (default 7)
#   --fixture DIR   JSON stand-in, no network
#   --ftl-db PATH   read a copy of pihole-FTL.db
#   --state PATH    known-client file (default under $XDG_STATE_HOME)
#
# Environment: PIHOLE_URL, PIHOLE_PASSWORD or PIHOLE_PASSWORD_FILE,
# PIHOLE_FTL_DB, PIHOLE_API_TOKEN (v5 is a short rolling window; see the README).
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
SUFFIXES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../pihole-tv" && pwd)/acr-suffixes.txt"
MODE="ask"
PY_ARGS=(--suffixes "$SUFFIXES")
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --ask) MODE="ask" ;;
    --yes|-y) MODE="apply" ;;
    --days)
      shift
      [[ $# -gt 0 ]] || { echo "error: --days needs a number" >&2; exit 1; }
      PY_ARGS+=(--days "$1")
      ;;
    --fixture)
      shift
      [[ $# -gt 0 ]] || { echo "error: --fixture needs a directory" >&2; exit 1; }
      PY_ARGS+=(--fixture "$1")
      ;;
    --ftl-db)
      shift
      [[ $# -gt 0 ]] || { echo "error: --ftl-db needs a path" >&2; exit 1; }
      PY_ARGS+=(--ftl-db "$1")
      ;;
    --state)
      shift
      [[ $# -gt 0 ]] || { echo "error: --state needs a path" >&2; exit 1; }
      PY_ARGS+=(--state "$1")
      ;;
    --output)
      shift
      [[ $# -gt 0 ]] || { echo "error: --output needs a path" >&2; exit 1; }
      OUTPUT="$1"
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
  read -r -p "Save the report and remember these clients for next time? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

python3 "$LIB/pihole.py" "${PY_ARGS[@]}" report

if [[ "$MODE" == "dry-run" ]]; then
  echo "(dry run) Did not write a report file and did not update the known-client list."
  exit 0
fi

if [[ "$MODE" == "ask" ]]; then
  if [[ -n "$OUTPUT" ]]; then
    echo "Save path: $OUTPUT"
  else
    echo "Save path: the privacy-sweep state directory (see the README)."
  fi
  confirm || { echo "Cancelled. Nothing saved."; exit 0; }
fi

SAVE_ARGS=(--save)
if [[ -n "$OUTPUT" ]]; then
  SAVE_ARGS+=(--output "$OUTPUT")
fi
python3 "$LIB/pihole.py" "${PY_ARGS[@]}" "${SAVE_ARGS[@]}" report >/dev/null
echo "Report saved."
