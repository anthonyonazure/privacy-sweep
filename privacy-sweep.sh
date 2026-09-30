#!/usr/bin/env bash
# privacy-sweep.sh - top-level launcher.
# Detects your operating system and runs the matching full sweep. Your flags
# pass straight through, so this behaves exactly like the per-OS clear-all:
#   ./privacy-sweep.sh --dry-run    # show what would be cleared, delete nothing
#   ./privacy-sweep.sh              # ask before each step
#   ./privacy-sweep.sh --yes        # clear everything, no prompts
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Darwin)
    echo "Detected: macOS"
    exec bash "$DIR/macos/clear-all.sh" "$@"
    ;;
  Linux)
    echo "Detected: Linux"
    exec bash "$DIR/linux/clear-all.sh" "$@"
    ;;
  *)
    echo "This launcher supports macOS and Linux. Detected: $(uname -s)."
    echo "On Windows, open Terminal as Administrator and run:  .\\privacy-sweep.ps1"
    exit 1
    ;;
esac
