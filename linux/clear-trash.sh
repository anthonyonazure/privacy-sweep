#!/usr/bin/env bash
# clear-trash.sh - part of privacy-sweep (Linux)
# Empties the desktop Trash (~/.local/share/Trash), files and metadata both.
# Note: emptying marks space reusable; it does not overwrite the bytes.
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

TRASH="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"

echo "== Trash =="
if [[ ! -d "$TRASH" ]]; then echo "No Trash folder found. Nothing to do."; exit 0; fi
SIZE=$(du -sh "$TRASH" 2>/dev/null | cut -f1)
COUNT=$(find "$TRASH/files" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
echo "Target: $TRASH   Items: ${COUNT:-0}   Size: ${SIZE:-0}"

if $DRY_RUN; then echo "(dry run) Would empty $TRASH/files and $TRASH/info."; exit 0; fi
confirm || { echo "Cancelled."; exit 0; }

find "$TRASH/files" -mindepth 1 -delete 2>/dev/null || true
find "$TRASH/info"  -mindepth 1 -delete 2>/dev/null || true
echo "Done. Trash emptied."
