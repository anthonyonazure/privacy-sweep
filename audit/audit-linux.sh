#!/usr/bin/env bash
# audit-linux.sh - part of privacy-sweep (report only)
# Prints counts and paths for the Linux stores a forensic examiner would look
# at first: thumbnail cache, recent documents, and shell history.
# It does not delete anything. It does not print file contents, so command
# history and document titles stay out of the terminal scrollback.
#
#   ./audit-linux.sh
#   ./audit-linux.sh --dry-run     # same report; there is nothing to apply
#   ./audit-linux.sh --yes         # same report
#
# Also reports swap, LUKS status (no keys), and wipe-tool remnant names.
# Login records (utmp, wtmp, btmp, lastlog) are out of scope, on purpose.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
  case "$arg" in
    --dry-run|--yes|-y) ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This report is for Linux. Detected: $(uname -s)." >&2
  exit 1
fi

echo "== Linux privacy audit (counts and paths, nothing deleted) =="
echo "Report only. This does not clear these stores."
echo

report_file() {
  local label="$1" path="$2"
  echo "-- $label --"
  if [[ ! -e "$path" ]]; then
    echo "Path: $path"
    echo "Count: 0 (not present)"
    echo
    return
  fi
  local lines="?"
  if [[ -f "$path" ]]; then
    lines="$(wc -l < "$path" | tr -d ' ')"
  fi
  echo "Path: $path"
  echo "Lines: $lines"
  echo
}

echo "-- Thumbnail cache --"
THUMBS="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails"
echo "Path: $THUMBS"
if [[ -d "$THUMBS" ]]; then
  COUNT="$(find "$THUMBS" -type f 2>/dev/null | wc -l | tr -d ' ')"
  SIZE="$(du -sh "$THUMBS" 2>/dev/null | cut -f1)"
  echo "Files: $COUNT"
  echo "Size: ${SIZE:-unknown}"
  echo "Subdirectories:"
  find "$THUMBS" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's/^/  /' || true
  echo "Individual thumbnail paths are not listed; the names are opaque hashes."
else
  echo "Files: 0 (not present)"
fi
echo

echo "-- Recently used files --"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
for target in "$DATA/recently-used.xbel" "$HOME/.recently-used.xbel"; do
  echo "Path: $target"
  if [[ -f "$target" ]]; then
    BOOKMARKS="$(grep -c '<bookmark ' "$target" 2>/dev/null || true)"
    echo "Bookmark entries: ${BOOKMARKS:-0}"
    echo "The document URIs inside the file are not printed."
  else
    echo "Bookmark entries: 0 (not present)"
  fi
done
RECENT_DIR="$DATA/RecentDocuments"
echo "Path: $RECENT_DIR"
if [[ -d "$RECENT_DIR" ]]; then
  echo "Files: $(find "$RECENT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
else
  echo "Files: 0 (not present)"
fi
echo

echo "-- Shell and tool history (line counts only) --"
for target in "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.viminfo" "$HOME/.lesshst" "$HOME/.python_history"; do
  report_file "$(basename "$target")" "$target"
done

bash "$DIR/audit-recovery-linux.sh" "$@"

echo "Swap, LUKS status, and wipe-tool remnant names are reported above."
echo "Nothing in this audit is deleted. Snapshot and shadow-copy purge is not"
echo "part of this tool. See docs/leave-no-trace.md."
echo "Not included, and not cleared by this tool: utmp, wtmp, btmp, lastlog,"
echo "the systemd journal, and other logs under /var/log."
echo "See SECURITY.md. The clear-* scripts are separate and ask before deleting."
