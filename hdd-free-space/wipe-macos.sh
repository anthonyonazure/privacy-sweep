#!/usr/bin/env bash
# wipe-macos.sh - explains why this repo does not fill free space on macOS.
# APFS Macs are usually SSDs. A fill file does not reliably erase NAND.
# Nothing in this script deletes files, snapshots, or Document Revisions.
#
#   ./wipe-macos.sh --help
#   ./wipe-macos.sh --dry-run     # exit 0, still writes nothing
#   ./wipe-macos.sh               # exit 2, writes nothing
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --dry-run) DRY_RUN=true ;;
    --yes|-y|--simulate|--i-know-this-is-ssd) ;;
    --volume)
      [[ $# -ge 2 ]] || { echo "Missing path after --volume" >&2; exit 1; }
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

cat <<EOF
macOS free-space fill is not provided.
APFS volumes on Macs are usually SSDs. Filling free space is theater there:
TRIM, wear leveling, and overprovisioned NAND are outside a userspace file.
This script does not delete local snapshots or Document Revisions.
Nothing was written.
Read ${ROOT}/docs/leave-no-trace.md
EOF

if [[ "$DRY_RUN" == true ]]; then
  exit 0
fi
exit 2
