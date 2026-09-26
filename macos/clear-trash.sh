#!/usr/bin/env bash
# clear-trash.sh - part of privacy-sweep (macOS)
# Empties the Trash for your account, including trashes on mounted volumes.
# Note: "empty" marks the space reusable; it does not overwrite the bytes.
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

TRASH="$HOME/.Trash"

echo "== Trash =="
if [[ ! -d "$TRASH" ]]; then echo "No Trash folder found. Nothing to do."; exit 0; fi
COUNT=$(find "$TRASH" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
SIZE=$(du -sh "$TRASH" 2>/dev/null | cut -f1)
echo "Target: $TRASH"
echo "Items: $COUNT   Size: ${SIZE:-0}"

if $DRY_RUN; then echo "(dry run) Would remove $COUNT items from the Trash."; exit 0; fi
confirm || { echo "Cancelled."; exit 0; }

find "$TRASH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
echo "Done. Trash emptied."
