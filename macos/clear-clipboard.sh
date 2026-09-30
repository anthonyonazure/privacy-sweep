#!/usr/bin/env bash
# clear-clipboard.sh - part of privacy-sweep (macOS)
# Wipes the current clipboard contents. macOS normally holds only one item, but
# macOS 26 added an optional clipboard history in Spotlight (Cmd+Space, Cmd+4).
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

echo "== Clipboard =="
echo "Target: the current pasteboard contents (cleared via pbcopy)."

if $DRY_RUN; then echo "(dry run) Would empty the clipboard."; exit 0; fi
confirm || { echo "Cancelled."; exit 0; }

: | pbcopy 2>/dev/null || true
echo "Done. Clipboard emptied."
echo "To turn off the running clipboard history: System Settings > Spotlight, and disable Clipboard history."
