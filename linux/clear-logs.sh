#!/usr/bin/env bash
# clear-logs.sh - part of privacy-sweep (Linux)  [ADMIN, OPT-IN]
# Vacuums the systemd journal and truncates common /var/log files. This is a
# SYSTEM ADMINISTRATION action, not everyday privacy hygiene: these logs are how
# you (and legitimate admins) diagnose crashes, break-ins and hardware faults.
# Only run this on a machine you administer, and only if you understand you are
# discarding that diagnostic history. NOT included in clear-all.sh by default.
# Modes: --dry-run (show only), (default) ask first, --yes (no prompt).
set -euo pipefail

DRY_RUN=false; ASSUME_YES=false
for arg in "$@"; do case "$arg" in
  --dry-run) DRY_RUN=true ;;
  --yes|-y) ASSUME_YES=true ;;
  --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $arg" >&2; exit 1 ;;
esac; done

confirm() { $ASSUME_YES && return 0; read -r -p "This discards system diagnostic logs. Proceed? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

if [[ $EUID -ne 0 ]]; then echo "This script needs root. Re-run with: sudo $0 $*"; exit 1; fi

echo "== System logs (journal + /var/log) =="
echo "Target: systemd journal (journalctl --vacuum-time=1s) and *.log files under /var/log"

if $DRY_RUN; then
  echo "(dry run) Would vacuum the journal and truncate:"
  find /var/log -type f -name '*.log' 2>/dev/null | head -20 | sed 's/^/  /'
  exit 0
fi
confirm || { echo "Cancelled."; exit 0; }

command -v journalctl >/dev/null 2>&1 && journalctl --rotate 2>/dev/null && journalctl --vacuum-time=1s 2>/dev/null || true
find /var/log -type f -name '*.log' -exec truncate -s 0 {} \; 2>/dev/null || true
echo "Done. Journal vacuumed and *.log files truncated."
