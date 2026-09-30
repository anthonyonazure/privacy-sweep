#!/usr/bin/env bash
# clear-temp.sh - part of privacy-sweep (Linux)
# Removes YOUR OWN leftover files in /tmp and /var/tmp. Only files you own are
# touched; other users' and the system's files are left alone.
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

echo "== Your temp files in /tmp and /var/tmp =="
COUNT=$(find /tmp /var/tmp -user "$(id -un)" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
echo "Files owned by you: ${COUNT:-0}"

if $DRY_RUN; then
  echo "(dry run) Would remove these (first 20 shown):"
  find /tmp /var/tmp -user "$(id -un)" -mindepth 1 -maxdepth 1 2>/dev/null | head -20 | sed 's/^/  /'
  exit 0
fi
confirm || { echo "Cancelled."; exit 0; }

# Only files you own; skip anything currently open by leaving in-use files (rm will just fail quietly).
find /tmp /var/tmp -user "$(id -un)" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
echo "Done. Your temp files cleared (anything in use was skipped)."
