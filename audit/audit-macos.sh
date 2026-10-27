#!/usr/bin/env bash
# audit-macos.sh - part of privacy-sweep (report only)
# Prints counts and paths for the macOS stores a forensic examiner would look
# at first: the download quarantine log, recent items, the Quick Look cache,
# shell history, unified logs, knowledgeC, Biome, and FSEvents.
# It does not delete anything and it does not print the contents of those stores.
# It also reports local snapshots, Document Revisions size, external Trash
# counts, sleepimage/swap presence, and FileVault on/off.
#
#   ./audit-macos.sh
#   ./audit-macos.sh --dry-run     # same report; there is nothing to apply
#   ./audit-macos.sh --yes         # same report
#
# Spotlight and the keychain are not read. Unified logs, knowledgeC, Biome,
# and FSEvents are reported as presence and size only.
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
echo
report_any() {
  local path="$1"
  echo "Path: $path"
  if [[ -d "$path" ]]; then
    if [[ -r "$path" && -x "$path" ]]; then
      local count size
      count="$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
      size="$(du -sh "$path" 2>/dev/null | cut -f1 || true)"
      echo "Present: yes"
      echo "Files: ${count:-unknown}"
      echo "Size: ${size:-unknown}"
      echo "Individual files are not listed."
    else
      echo "Present: yes (not readable from this account)"
    fi
  elif [[ -f "$path" ]]; then
    echo "Present: yes"
    if [[ -r "$path" ]]; then
      echo "Size: $(stat -f '%z' "$path" 2>/dev/null || echo unknown) bytes"
    else
      echo "Size: unreadable from this account"
    fi
  elif [[ -e "$path" ]]; then
    echo "Present: yes"
  else
    echo "Present: no (or not visible to this account)"
  fi
}

echo "-- Unified logs --"
echo "Log messages are not printed. This does not run 'log show'."
report_any "/private/var/db/diagnostics"
echo

echo "-- knowledgeC.db (presence and size) --"
echo "Rows are not queried."
report_any "$HOME/Library/Application Support/Knowledge/knowledgeC.db"
report_any "$HOME/Library/Application Support/Knowledge/knowledgeC.db-wal"
report_any "/private/var/db/CoreDuet/Knowledge/knowledgeC.db"
echo

echo "-- Biome (presence and size) --"
echo "Stream contents are not printed."
report_any "$HOME/Library/Biome"
report_any "/private/var/db/biome"
echo

echo "-- FSEvents --"
echo "Changed paths inside the logs are not printed."
report_any "/.fseventsd"
report_any "/System/Volumes/Data/.fseventsd"
echo

bash "$DIR/audit-recovery-macos.sh" "$@"

echo "Local snapshots, Document Revisions, external Trash, sleepimage/swap,"
echo "and FileVault on/off are reported above. They are not deleted."
echo "Unified logs, knowledgeC, Biome, and FSEvents are reported as presence"
echo "and size only. Rows, log messages, and changed paths are not printed."
echo "Not read, and not cleared by this tool: Spotlight and the keychain."
echo "See SECURITY.md and docs/leave-no-trace.md."
