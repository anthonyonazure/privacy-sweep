#!/usr/bin/env bash
# clear-all.sh - part of privacy-sweep (Linux)
# Runs the user-space clear-* scripts in this folder, passing your flags to each.
# It deliberately does NOT run clear-logs.sh: that one is an admin action you
# invoke on purpose.
# Modes: --dry-run (show only, run first), (default) ask per step, --yes (no prompt).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=("$@")

echo "#############################################"
echo "# privacy-sweep - Linux - full run"
echo "#############################################"
echo

for s in clear-thumbnails.sh clear-recent.sh clear-trash.sh clear-shell-history.sh clear-temp.sh; do
  if [[ -f "$DIR/$s" ]]; then
    echo "----- $s -----"
    bash "$DIR/$s" "${PASS[@]}" || echo "(!) $s exited non-zero, continuing"
    echo
  fi
done

echo "All user-space Linux steps finished."
echo "System logs are separate and admin-only: sudo ./clear-logs.sh"
echo "Reminder: the durable fix is full-disk encryption (LUKS)."
