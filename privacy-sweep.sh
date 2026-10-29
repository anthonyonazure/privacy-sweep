#!/usr/bin/env bash
# privacy-sweep.sh - top-level launcher.
# Detects your operating system and runs the matching full sweep. Your flags
# pass straight through, so this behaves exactly like the per-OS clear-all:
#   ./privacy-sweep.sh --dry-run    # show what would be cleared, delete nothing
#   ./privacy-sweep.sh              # ask before each step
#   ./privacy-sweep.sh --yes        # clear everything, no prompts
#
#   ./privacy-sweep.sh --dry-run --all-modules
#     Dry-run the per-OS sweep and every opt-in module. Deletes nothing.
#     If --all-modules is given without --dry-run, a dry run is forced.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALL=false
PASS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all-modules) ALL=true ;;
    *) PASS+=("$1") ;;
  esac
  shift
done

if [[ "$ALL" == true ]]; then
  has_dry=false
  if [[ ${#PASS[@]} -gt 0 ]]; then
    for arg in "${PASS[@]}"; do
      if [[ "$arg" == "--dry-run" ]]; then
        has_dry=true
      fi
    done
  fi
  if [[ "$has_dry" != true ]]; then
    echo "--all-modules forces a dry run. Nothing will be deleted."
  fi
  # shellcheck source=lib/all-modules.sh
  source "$DIR/lib/all-modules.sh"
  run_all_modules
  exit 0
fi

run_clear_all() {
  local script="$1"
  if [[ ${#PASS[@]} -gt 0 ]]; then
    exec bash "$script" "${PASS[@]}"
  fi
  exec bash "$script"
}

case "$(uname -s)" in
  Darwin)
    echo "Detected: macOS"
    run_clear_all "$DIR/macos/clear-all.sh"
    ;;
  Linux)
    echo "Detected: Linux"
    run_clear_all "$DIR/linux/clear-all.sh"
    ;;
  *)
    echo "This launcher supports macOS and Linux. Detected: $(uname -s)."
    echo "On Windows, open Terminal as Administrator and run:  .\\privacy-sweep.ps1"
    echo "To dry-run every Windows module:  .\\privacy-sweep.ps1 -DryRun -AllModules"
    exit 1
    ;;
esac
