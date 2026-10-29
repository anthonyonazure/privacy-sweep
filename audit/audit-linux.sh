#!/usr/bin/env bash
# audit-linux.sh - part of privacy-sweep (report only)
# Prints counts and paths for the Linux stores a forensic examiner would look
# at first: thumbnail cache, recent documents, shell history, screenshot
# folders, journal size, login-record files, and whether a user crontab exists.
# It does not delete anything. It does not print file contents, so command
# history, document titles, screenshot names, journal text, login lines, and
# crontab commands stay out of the terminal scrollback.
#
#   ./audit-linux.sh
#   ./audit-linux.sh --dry-run     # same report; there is nothing to apply
#   ./audit-linux.sh --yes         # same report
#
# Also reports swap, LUKS status (no keys), and wipe-tool remnant names.
# recently-used.xbel is already counted with recent documents.
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
  COUNT="$(find "$THUMBS" -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
  SIZE="$(du -sh "$THUMBS" 2>/dev/null | cut -f1 || true)"
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
  echo "Files: $(find "$RECENT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
else
  echo "Files: 0 (not present)"
fi
echo

echo "-- Shell and tool history (line counts only) --"
for target in \
  "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.viminfo" "$HOME/.lesshst" "$HOME/.python_history" \
  "$HOME/.local/share/fish/fish_history" "$HOME/.config/fish/fish_history" \
  "$HOME/.sh_history" "$HOME/.ksh_history" "$HOME/.history" "$HOME/.csh_history" \
  "$HOME/.config/nushell/history.txt" "$HOME/.local/share/ion/history"; do
  report_file "$(basename "$target")" "$target"
done

echo "-- Screenshot folders --"
echo "File names are not listed. A name can describe what was on the screen."
pictures="$HOME/Pictures"
dirs_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
if [[ -f "$dirs_file" ]]; then
  raw=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      XDG_PICTURES_DIR=*) raw="${line#XDG_PICTURES_DIR=}"; break ;;
    esac
  done < "$dirs_file"
  raw="${raw%\"}"
  raw="${raw#\"}"
  # user-dirs.dirs stores the home directory as the two characters '$' and 'HOME'.
  home_token="$(printf '%s%s' '$' 'HOME')"
  if [[ "$raw" == "$home_token"/* ]]; then
    raw="$HOME/${raw#"$home_token"/}"
  fi
  case "$raw" in
    "$HOME"/*) pictures="$raw" ;;
  esac
fi
seen=$'\n'
report_dir() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  case "$seen" in
    *$'\n'"$path"$'\n'*) return 0 ;;
  esac
  seen="$seen$path"$'\n'
  echo "Path: $path"
  if [[ -d "$path" ]]; then
    local count size
    count="$(find "$path" -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
    size="$(du -sh "$path" 2>/dev/null | cut -f1 || true)"
    echo "Present: yes"
    echo "Files: ${count:-unknown}"
    echo "Size: ${size:-unknown}"
  elif [[ -e "$path" ]]; then
    echo "Present: yes (not a directory)"
  else
    echo "Present: no"
  fi
}
report_dir "$pictures/Screenshots"
report_dir "$HOME/Pictures/Screenshots"
report_dir "$HOME/Pictures/screenshots"
report_dir "$HOME/Screenshots"
echo

echo "-- systemd journal (size only) --"
if command -v journalctl >/dev/null 2>&1; then
  usage="$(journalctl --disk-usage 2>/dev/null || true)"
  if [[ "$usage" == *"take up"* ]]; then
    echo "$usage"
  else
    echo "journalctl is installed, but this account could not read the disk usage."
  fi
else
  echo "journalctl: not installed"
fi
for target in /var/log/journal /run/log/journal; do
  echo "Path: $target"
  if [[ -d "$target" ]]; then
    if [[ -r "$target" && -x "$target" ]]; then
      echo "Present: yes"
      echo "Size: $(du -sh "$target" 2>/dev/null | cut -f1 || true)"
    else
      echo "Present: yes (not readable from this account)"
    fi
  else
    echo "Present: no (or not visible to this account)"
  fi
done
echo "Journal messages are not printed."
echo

echo "-- Login records (presence and size only) --"
echo "Who logged in is not printed, and these files are not edited."
for target in /var/log/wtmp /var/log/lastlog /var/log/btmp; do
  echo "Path: $target"
  if [[ -f "$target" ]]; then
    if [[ -r "$target" ]]; then
      echo "Present: yes"
      echo "Size: $(stat -c '%s' "$target" 2>/dev/null || echo unknown) bytes"
    else
      echo "Present: yes (not readable from this account)"
    fi
  elif [[ -e "$target" ]]; then
    echo "Present: yes"
  else
    echo "Present: no (or not visible to this account)"
  fi
done
echo

echo "-- User crontab (presence only) --"
user_name="$(id -un)"
for target in "/var/spool/cron/crontabs/$user_name" "/var/spool/cron/$user_name"; do
  echo "Path: $target"
  if [[ -f "$target" ]]; then
    if [[ -r "$target" ]]; then
      echo "Present: yes"
      echo "Size: $(stat -c '%s' "$target" 2>/dev/null || echo unknown) bytes"
    else
      echo "Present: yes (not readable from this account)"
    fi
    echo "Commands in the file are not printed."
  elif [[ -e "$target" ]]; then
    echo "Present: yes"
  else
    echo "Present: no (or not visible to this account)"
  fi
done
if command -v crontab >/dev/null 2>&1; then
  cron_status=0
  cron_err="$(crontab -l 2>&1 >/dev/null)" || cron_status=$?
  if [[ "$cron_status" -eq 0 ]]; then
    echo "crontab -l: a crontab is installed for $user_name (commands not printed)."
  elif [[ "$cron_err" == *"no crontab"* ]]; then
    echo "crontab -l: no crontab for $user_name."
  else
    echo "crontab -l: could not be checked from this account."
  fi
else
  echo "crontab: not installed"
fi
echo

bash "$DIR/audit-recovery-linux.sh" "$@"

echo "Screenshot folders, journal size, login-record sizes, and crontab presence"
echo "are reported above. Swap, LUKS status, and wipe-tool remnant names are too."
echo "File contents, journal messages, who logged in, and crontab commands are not printed."
echo "Nothing in this audit is deleted. This report does not edit login records or the journal."
echo "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
echo "Nothing was deleted."
echo "Opt-in snapshot purge, browser-deep, and memory actions are separate tools and are not part of clear-all."
echo "See SECURITY.md and docs/leave-no-trace.md."
