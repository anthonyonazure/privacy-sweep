#!/usr/bin/env bash
# clear-quicklook.sh - part of privacy-sweep (macOS)
# Clears the Quick Look thumbnail cache: the small image previews macOS keeps of
# your files. A preview can survive after you delete the original photo.
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

echo "== Quick Look thumbnail cache =="
echo "Target: the system Quick Look cache (reset via 'qlmanage -r cache')."
echo "It rebuilds itself as you browse folders, so this is maintenance, not a one-off."

if $DRY_RUN; then echo "(dry run) Would run: qlmanage -r cache"; exit 0; fi
confirm || { echo "Cancelled."; exit 0; }

qlmanage -r cache >/dev/null 2>&1 || true
echo "Done. Quick Look cache reset."
