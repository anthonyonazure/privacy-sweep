#!/usr/bin/env bash
# clear-recent.sh - part of privacy-sweep (macOS)
# Clears the "recent items" lists: recent documents, applications, servers, and
# the per-app Open Recent menus. These live in the sharedfilelist folder.
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

SFL="$HOME/Library/Application Support/com.apple.sharedfilelist"

echo "== Recent items (documents, apps, servers) =="
if [[ ! -d "$SFL" ]]; then echo "No recent-items store found. Nothing to do."; exit 0; fi
FILES=$(find "$SFL" -type f \( -name "*.sfl*" -o -name "*.plist" \) 2>/dev/null | wc -l | tr -d ' ')
echo "Target: $SFL"
echo "Recent-list files found: $FILES"

if $DRY_RUN; then
  echo "(dry run) Would delete these lists:"
  find "$SFL" -type f \( -name "*.sfl*" -o -name "*.plist" \) 2>/dev/null | sed 's/^/  /'
  echo "Would then restart Finder and Dock to apply."
  exit 0
fi
confirm || { echo "Cancelled."; exit 0; }

find "$SFL" -type f \( -name "*.sfl*" -o -name "*.plist" \) -delete 2>/dev/null || true
killall Finder Dock 2>/dev/null || true
echo "Done. Recent-items lists cleared (Finder and Dock restarted)."
echo "To stop new ones being kept: System Settings > Menu Bar > 'Recent documents...' > None."
