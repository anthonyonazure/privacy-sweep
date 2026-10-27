#!/usr/bin/env bash
# audit-macos.sh - part of privacy-sweep (report only)
# Prints counts and paths for the macOS stores a forensic examiner would look
# at first: the download quarantine log, recent items, the Quick Look cache,
# and shell history.
# It does not delete anything and it does not print the contents of those stores.
# It also reports local snapshots, Document Revisions size, external Trash
# counts, sleepimage/swap presence, and FileVault on/off.
#
#   ./audit-macos.sh
#   ./audit-macos.sh --dry-run     # same report; there is nothing to apply
#   ./audit-macos.sh --yes         # same report
#
# Spotlight, unified logs, knowledgeC, and the keychain are not read.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
  case "$arg" in
    --dry-run|--yes|-y) ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This report is for macOS. Detected: $(uname -s)." >&2
  exit 1
fi

echo "== macOS privacy audit (counts and paths, nothing deleted) =="
echo "Report only. This does not clear these stores."
echo

echo "-- Download log (QuarantineEventsV2) --"
DB="$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
echo "Path: $DB"
if [[ -f "$DB" ]]; then
  if command -v sqlite3 >/dev/null 2>&1; then
    COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM LSQuarantineEvent;" 2>/dev/null || echo "unreadable")"
    echo "Rows: $COUNT"
  else
    echo "Rows: unknown (sqlite3 is not installed)"
  fi
  echo "Download URLs are not printed."
else
  echo "Rows: 0 (not present)"
fi
echo

echo "-- Recent items --"
SFL="$HOME/Library/Application Support/com.apple.sharedfilelist"
echo "Path: $SFL"
if [[ -d "$SFL" ]]; then
  echo "Files: $(find "$SFL" -type f 2>/dev/null | wc -l | tr -d ' ')"
  find "$SFL" -type f 2>/dev/null | sed 's/^/  /'
else
  echo "Files: 0 (not present)"
fi
echo

echo "-- Quick Look thumbnail cache --"
QL="$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache"
echo "Path: $QL"
if [[ -d "$QL" ]]; then
  echo "Files: $(find "$QL" -type f 2>/dev/null | wc -l | tr -d ' ')"
  echo "Size: $(du -sh "$QL" 2>/dev/null | cut -f1)"
else
  echo "Files: 0 (this user cache is not present)"
fi
echo "clear-quicklook.sh resets the system cache with qlmanage. That cache"
echo "may also live outside your home folder; this report does not search the disk for it."
echo

echo "-- Shell history (line counts only) --"
shopt -s nullglob
HIST_FILES=("$HOME/.zsh_history" "$HOME/.bash_history" "$HOME/.zhistory")
HIST_FILES+=("$HOME"/.zsh_sessions/*.history "$HOME"/.zsh_sessions/*.historynew)
shopt -u nullglob
if [[ ${#HIST_FILES[@]} -eq 0 ]]; then
  echo "No history files found."
else
  for target in "${HIST_FILES[@]}"; do
    if [[ -f "$target" ]]; then
      echo "Path: $target"
      echo "Lines: $(wc -l < "$target" | tr -d ' ')"
    fi
  done
fi
bash "$DIR/audit-recovery-macos.sh" "$@"

echo "Local snapshots, Document Revisions, external Trash, sleepimage/swap,"
echo "and FileVault on/off are reported above. They are not deleted."
echo "Not included, and not cleared by this tool: Spotlight, the unified log,"
echo "knowledgeC, Biome, and the keychain. See SECURITY.md."
echo "knowledgeC and Biome are not read. See docs/leave-no-trace.md."
