#!/usr/bin/env bash
# clear-browser-deep.sh - LevelDB, IndexedDB, Cache_Data, service workers,
# session restore, and Crashpad dumps. Bookmarks are reported and never deleted.
# Opt-in. Dry-run unless --apply. Refuses a browser that is still running.
# Not part of clear-all.
#
#   ./clear-browser-deep.sh
#   ./clear-browser-deep.sh --dry-run --clear-browser-deep
#   ./clear-browser-deep.sh --clear-browser-deep --apply
#   ./clear-browser-deep.sh --clear-browser-deep --apply --only chrome
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=lib/confirm.sh
source "$ROOT/lib/confirm.sh"

DRY_RUN=false
APPLY=false
DO_CLEAR=false
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --apply) APPLY=true ;;
    --yes|-y) ;;
    --clear-browser-deep) DO_CLEAR=true ;;
    --only)
      shift
      [[ $# -gt 0 ]] || { echo "error: --only needs a comma-separated list" >&2; exit 1; }
      ONLY="$1"
      ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

OS="$(uname -s)"
case "$OS" in
  Linux|Darwin) ;;
  *) echo "This script supports macOS and Linux. On Windows run clear-browser-deep.ps1." >&2; exit 1 ;;
esac

if ! command -v pgrep >/dev/null 2>&1; then
  echo "pgrep is required so this script can refuse a running browser." >&2
  exit 1
fi

config_home() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }

_any_running() {
  local name
  for name in "$@"; do
    if pgrep -x "$name" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

browser_running() {
  local id="$1"
  case ",${PRIVACY_SWEEP_ASSUME_OPEN:-}," in
    *,"$id",*) return 0 ;;
  esac
  if [[ "$OS" == "Darwin" ]]; then
    case "$id" in
      chrome) _any_running "Google Chrome" ;;
      chromium) _any_running "Chromium" ;;
      edge) _any_running "Microsoft Edge" ;;
      brave) _any_running "Brave Browser" ;;
      firefox) _any_running "firefox" "Firefox" ;;
      safari) _any_running "Safari" ;;
      *) return 1 ;;
    esac
    return
  fi
  case "$id" in
    chrome) _any_running "chrome" "google-chrome" "google-chrome-stable" ;;
    chromium) _any_running "chromium" "chromium-browser" ;;
    edge) _any_running "msedge" "microsoft-edge" "microsoft-edge-stable" ;;
    brave) _any_running "brave" "brave-browser" ;;
    firefox) _any_running "firefox" "firefox-bin" ;;
    *) return 1 ;;
  esac
}

under_home() {
  local path="$1" real
  [[ -e "$path" ]] || return 1
  if [[ -d "$path" ]]; then
    real="$(cd "$path" && pwd -P)"
  else
    real="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  fi
  case "$real" in
    "$HOME"|"$HOME"/*) return 0 ;;
    *) return 1 ;;
  esac
}

want() {
  local id="$1"
  [[ -z "$ONLY" ]] && return 0
  case ",${ONLY// /}," in
    *,"$id",*) return 0 ;;
    *) return 1 ;;
  esac
}

chromium_profiles() {
  local root="$1" dir
  [[ -d "$root" ]] || return 0
  for dir in "$root/Default" "$root"/Profile\ * "$root/Guest Profile"; do
    [[ -d "$dir" ]] || continue
    printf '%s\n' "$dir"
  done
}

firefox_profiles() {
  local root ini path is_rel
  for root in "$HOME/.mozilla/firefox" "$(config_home)/mozilla/firefox"; do
    ini="$root/profiles.ini"
    [[ -f "$ini" ]] || continue
    path=""
    is_rel=1
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in
        Path=*) path="${line#Path=}" ;;
        IsRelative=0) is_rel=0 ;;
        IsRelative=1) is_rel=1 ;;
        \[*)
          if [[ -n "$path" ]]; then
            if [[ "$is_rel" -eq 1 ]]; then
              printf '%s\n' "$root/$path"
            else
              printf '%s\n' "$path"
            fi
          fi
          path=""
          is_rel=1
          ;;
      esac
    done < "$ini"
    if [[ -n "$path" ]]; then
      if [[ "$is_rel" -eq 1 ]]; then
        printf '%s\n' "$root/$path"
      else
        printf '%s\n' "$path"
      fi
    fi
  done
}

safe_count() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo 0
    return 0
  fi
  if [[ -d "$path" ]]; then
    find -P "$path" -type f 2>/dev/null | wc -l | tr -d ' ' || true
  else
    echo 1
  fi
}

report_keep() {
  local path="$1" label="$2"
  echo "  KEEP $label"
  echo "    Path: $path"
  if [[ -e "$path" ]]; then
    local bytes
    # The shell opens the redirection itself. Redirecting wc's stderr does
    # not hide "Operation not permitted" from that open.
    bytes="$( { wc -c < "$path" | tr -d ' '; } 2>/dev/null )" || true
    if [[ -z "${bytes:-}" ]]; then
      echo "    present (not readable: macOS privacy protection)"
    else
      echo "    Present: yes  Bytes: $bytes"
    fi
  else
    echo "    Present: no"
  fi
  echo "    Contents are not printed. This file is not deleted."
}

ACTIONS=()
REFUSED=0

queue_path() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  under_home "$path" || { echo "  Skipping $path (outside your home directory)."; return 0; }
  local count
  count="$(safe_count "$path")"
  echo "  CLEAR $path  (files: ${count:-0})"
  ACTIONS+=("$path")
}

report_bookmarks_sqlite() {
  local db="$1"
  report_keep "$db" "Firefox places.sqlite (bookmarks live here; not deleted)"
  if [[ -f "$db" ]] && command -v sqlite3 >/dev/null 2>&1; then
    local count
    count="$(sqlite3 "$db" "SELECT COUNT(*) FROM moz_bookmarks;" 2>/dev/null || true)"
    if [[ -n "$count" ]]; then
      echo "    Bookmark rows: $count"
      echo "    Bookmark titles and URLs are not printed."
    fi
  fi
}

queue_chromium() {
  local id="$1" label="$2" root="$3"
  echo "-- $label --"
  if [[ ! -d "$root" ]]; then
    echo "  Not installed ($root)."
    return 0
  fi
  if browser_running "$id"; then
    echo "  REFUSED: $label is running. Quit $label and run this script again."
    REFUSED=1
    return 0
  fi
  local profile base
  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    echo "  Profile: $profile"
    report_keep "$profile/Bookmarks" "bookmarks"
    report_keep "$profile/Bookmarks.bak" "bookmarks backup"
    if [[ "$DO_CLEAR" != true ]]; then
      continue
    fi
    local rel
    for rel in \
      "Local Storage/leveldb" \
      "IndexedDB" \
      "Session Storage" \
      "Service Worker" \
      "Cache/Cache_Data" \
      "Sessions" \
      "Current Session" \
      "Current Tabs" \
      "Last Session" \
      "Last Tabs"
    do
      queue_path "$profile/$rel"
    done
  done < <(chromium_profiles "$root")
  if [[ "$DO_CLEAR" == true ]]; then
    queue_path "$root/Crashpad"
    queue_path "$root/Crash Reports"
  else
    echo "  Crashpad: $(safe_count "$root/Crashpad") files (not listed)"
  fi
  base="$(basename "$root")"
  echo "  Bookmarks for $base are not deleted."
}

queue_firefox() {
  echo "-- Firefox --"
  if browser_running firefox; then
    echo "  REFUSED: Firefox is running. Quit Firefox and run this script again."
    REFUSED=1
    return 0
  fi
  local profile found=0
  while IFS= read -r profile; do
    [[ -n "$profile" && -d "$profile" ]] || continue
    under_home "$profile" || { echo "  Skipping $profile (outside your home directory)."; continue; }
    found=1
    echo "  Profile: $profile"
    report_bookmarks_sqlite "$profile/places.sqlite"
    if [[ "$DO_CLEAR" != true ]]; then
      continue
    fi
    queue_path "$profile/storage/default"
    queue_path "$profile/sessionstore.jsonlz4"
    queue_path "$profile/sessionstore.js"
    queue_path "$profile/sessionCheckpoints.json"
    queue_path "$profile/sessionstore-backups"
    queue_path "$profile/minidumps"
    queue_path "$profile/crashes"
  done < <(firefox_profiles | awk 'NF && !seen[$0]++')
  if [[ "$found" -eq 0 ]]; then
    echo "  Not installed (no profiles.ini)."
  fi
}

queue_safari() {
  echo "-- Safari --"
  if [[ "$OS" != "Darwin" ]]; then
    echo "  Safari is part of macOS. Nothing to do here."
    return 0
  fi
  if browser_running safari; then
    echo "  REFUSED: Safari is running. Quit Safari and run this script again."
    REFUSED=1
    return 0
  fi
  report_keep "$HOME/Library/Safari/Bookmarks.plist" "Safari bookmarks"
  if [[ "$DO_CLEAR" != true ]]; then
    return 0
  fi
  queue_path "$HOME/Library/Safari/LocalStorage"
  queue_path "$HOME/Library/Safari/Databases"
  queue_path "$HOME/Library/Safari/LastSession.plist"
  queue_path "$HOME/Library/Caches/com.apple.Safari"
  queue_path "$HOME/Library/Containers/com.apple.Safari/Data/Library/Caches"
  local reports="$HOME/Library/Logs/DiagnosticReports"
  if [[ -d "$reports" ]]; then
    local count
    count="$(find -P "$reports" -maxdepth 1 -type f -name 'Safari*' 2>/dev/null | wc -l | tr -d ' ' || true)"
    echo "  Safari diagnostic reports: ${count:-0} (names not listed; not deleted by this script)"
  fi
}

echo "== Browser deep stores (LevelDB, IndexedDB, session restore, Crashpad) =="
echo "Bookmarks are reported and are never deleted."
echo "Pass --clear-browser-deep to plan a clear. Pass --apply as well to delete."
echo "--yes does not delete. This is not part of clear-all."
echo

if want chrome; then
  if [[ "$OS" == "Darwin" ]]; then
    queue_chromium chrome "Chrome" "$HOME/Library/Application Support/Google/Chrome"
  else
    queue_chromium chrome "Chrome" "$(config_home)/google-chrome"
  fi
fi
if want chromium; then
  if [[ "$OS" == "Darwin" ]]; then
    queue_chromium chromium "Chromium" "$HOME/Library/Application Support/Chromium"
  else
    queue_chromium chromium "Chromium" "$(config_home)/chromium"
  fi
fi
if want edge; then
  if [[ "$OS" == "Darwin" ]]; then
    queue_chromium edge "Edge" "$HOME/Library/Application Support/Microsoft Edge"
  else
    queue_chromium edge "Edge" "$(config_home)/microsoft-edge"
  fi
fi
if want brave; then
  if [[ "$OS" == "Darwin" ]]; then
    queue_chromium brave "Brave" "$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
  else
    queue_chromium brave "Brave" "$(config_home)/BraveSoftware/Brave-Browser"
  fi
fi
if want firefox; then
  queue_firefox
fi
if want safari; then
  queue_safari
fi

echo
echo "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."

if [[ "$DO_CLEAR" != true ]]; then
  echo "Nothing was deleted."
  exit 0
fi

if [[ ${#ACTIONS[@]} -eq 0 ]]; then
  if [[ "$REFUSED" -eq 1 ]]; then
    echo "Nothing was cleared. At least one browser was open."
    exit 2
  fi
  echo "No deep browser stores found for the selected browsers."
  echo "Nothing was deleted."
  exit 0
fi

if [[ "$APPLY" != true || "$DRY_RUN" == true ]]; then
  echo "Dry run: would clear ${#ACTIONS[@]} path(s). Nothing was deleted."
  if [[ "$REFUSED" -eq 1 ]]; then
    exit 2
  fi
  exit 0
fi

if ! confirm_yn "Clear the browser deep stores listed above? Bookmarks stay"; then
  echo "Cancelled. Nothing was deleted."
  if [[ "$REFUSED" -eq 1 ]]; then
    exit 2
  fi
  exit 0
fi

for path in "${ACTIONS[@]}"; do
  case "$(basename "$path")" in
    Bookmarks|Bookmarks.bak|Bookmarks.plist|places.sqlite|Login\ Data|key4.db|logins.json)
      echo "Refusing to delete $path"
      continue
      ;;
  esac
  if [[ -d "$path" ]]; then
    find -P "$path" -mindepth 1 -delete 2>/dev/null || true
  elif [[ -f "$path" ]]; then
    rm -f -- "$path"
  fi
done

echo "Done. Bookmarks were not deleted."
if [[ "$REFUSED" -eq 1 ]]; then
  exit 2
fi
