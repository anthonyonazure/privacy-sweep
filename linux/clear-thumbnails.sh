#!/usr/bin/env bash
# clear-thumbnails.sh - part of privacy-sweep (Linux)
# Clears the desktop thumbnail cache (~/.cache/thumbnails). GNOME, KDE and most
# file managers keep image previews here, which can outlive the originals.
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

DIR="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails"

echo "== Thumbnail cache =="
if [[ ! -d "$DIR" ]]; then echo "No thumbnail cache found. Nothing to do."; exit 0; fi
SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1)
echo "Target: $DIR   Size: ${SIZE:-0}"

if $DRY_RUN; then echo "(dry run) Would delete the contents of $DIR."; exit 0; fi
confirm || { echo "Cancelled."; exit 0; }

find "$DIR" -mindepth 1 -delete 2>/dev/null || true
echo "Done. Thumbnail cache cleared. It rebuilds as you browse folders."
