#!/usr/bin/env bash
# audit.sh - report-only launcher.
# Runs the audit for this operating system. Every flag is passed through.
# The report prints counts and paths, including execution stores, knowledge
# databases, login records, and recovery structures. It does not delete anything.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OS_NAME="${PRIVACY_SWEEP_OS:-$(uname -s)}"
case "$OS_NAME" in
  Darwin)
    exec bash "$DIR/audit-macos.sh" "$@"
    ;;
  Linux)
    exec bash "$DIR/audit-linux.sh" "$@"
    ;;
  *)
    echo "This launcher supports macOS and Linux. Detected: $(uname -s)."
    printf '%s\n' 'On Windows run:  .\audit\audit-windows.ps1'
    exit 1
    ;;
esac
