#!/usr/bin/env bash
# clear-recent.sh - part of privacy-sweep (Linux)
# Clears the "recently used" file list (recently-used.xbel) that the desktop
# and file managers use to show recent documents.
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

DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
TARGETS=("$DATA/recently-used.xbel" "$HOME/.recently-used.xbel" "$DATA/RecentDocuments")

echo "== Recently used files =="
FOUND=()
for t in "${TARGETS[@]}"; do [[ -e "$t" ]] && FOUND+=("$t"); done
if [[ ${#FOUND[@]} -eq 0 ]]; then echo "No recent-files list found. Nothing to do."; exit 0; fi
printf 'Target: %s\n' "${FOUND[@]}"

if $DRY_RUN; then echo "(dry run) Would clear the item(s) above."; exit 0; fi
confirm || { echo "Cancelled."; exit 0; }

for t in "${FOUND[@]}"; do
  if [[ -d "$t" ]]; then find "$t" -mindepth 1 -delete 2>/dev/null || true
  else : > "$t"; fi
done
echo "Done. Recent-files list cleared."
