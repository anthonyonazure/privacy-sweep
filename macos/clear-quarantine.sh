#!/usr/bin/env bash
# clear-quarantine.sh - part of privacy-sweep (macOS)
# Clears the download log. macOS records every file you download and the web
# address it came from, in a database called QuarantineEventsV2. Clearing your
# browser history does NOT touch this. This is the one most people never see.
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

DB="$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"

echo "== Download log (QuarantineEventsV2) =="
if [[ ! -f "$DB" ]]; then echo "No download log found. Nothing to do."; exit 0; fi
COUNT=$(sqlite3 "$DB" "select count(*) from LSQuarantineEvent" 2>/dev/null || echo "?")
echo "Target: $DB"
echo "Entries recorded: $COUNT"

if $DRY_RUN; then echo "(dry run) Would delete all $COUNT rows from LSQuarantineEvent."; exit 0; fi
confirm || { echo "Cancelled."; exit 0; }

sqlite3 "$DB" "delete from LSQuarantineEvent; vacuum;" 2>/dev/null || true
echo "Done. Download log cleared."
