#!/usr/bin/env bash
# acr-clients.sh - part of privacy-sweep (Pi-hole)
# Reports which LAN clients looked up ACR / smart-TV telemetry names.
# Read-only. It does not edit Pi-hole and it does not delete the query log.
#
#   ./acr-clients.sh                 # print the report
#   ./acr-clients.sh --dry-run       # print the report, never write a file
#   ./acr-clients.sh --output FILE   # print, then ask before saving
#   ./acr-clients.sh --yes --output FILE
#
#   --days N       window length (default 7)
#   --fixture DIR  JSON stand-in, no network
#   --ftl-db PATH  read a copy of pihole-FTL.db instead of the API
#
# Environment: PIHOLE_URL, PIHOLE_PASSWORD or PIHOLE_PASSWORD_FILE,
# PIHOLE_FTL_DB, PIHOLE_API_TOKEN (v5; per-client ACR needs the database).
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
MODE="ask"
PY_ARGS=(--section acr --suffixes "$(dirname "${BASH_SOURCE[0]}")/acr-suffixes.txt")
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
  read -r -p "Save this report to ${OUTPUT}? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

python3 "$LIB/pihole.py" "${PY_ARGS[@]}" report

if [[ -z "$OUTPUT" || "$MODE" == "dry-run" ]]; then
  if [[ -n "$OUTPUT" && "$MODE" == "dry-run" ]]; then
    echo "(dry run) Did not write $OUTPUT."
  fi
  exit 0
fi

if [[ "$MODE" == "ask" ]]; then
  confirm || { echo "Cancelled. Nothing saved."; exit 0; }
fi

python3 "$LIB/pihole.py" "${PY_ARGS[@]}" --save --output "$OUTPUT" report >/dev/null
echo "Saved $OUTPUT"
