#!/usr/bin/env bash
# clear-all.sh - part of privacy-sweep (macOS)
# Runs every macOS clear-* script in this folder, passing your flags to each.
# Modes: --dry-run (show only, recommended first run), (default) ask per step,
#        --yes (no prompts, clear everything).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=("$@")

echo "#############################################"
echo "# privacy-sweep - macOS - full run"
echo "#############################################"
echo

for s in clear-quicklook.sh clear-quarantine.sh clear-recent.sh clear-trash.sh clear-shell-history.sh clear-clipboard.sh; do
  if [[ -x "$DIR/$s" || -f "$DIR/$s" ]]; then
    echo "----- $s -----"
    bash "$DIR/$s" "${PASS[@]}" || echo "(!) $s exited non-zero, continuing"
    echo
  fi
done

echo "All macOS steps finished."
echo "Reminder: the durable fix is FileVault (System Settings > Privacy & Security > FileVault)."
