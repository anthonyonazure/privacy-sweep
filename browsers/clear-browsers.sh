#!/usr/bin/env bash
# clear-browsers.sh - part of privacy-sweep
# Clears history, cookies, and cache for Chrome, Edge, Firefox, Safari, and
# Brave (and Chromium, which uses the same layout as Chrome). Bookmarks and
# saved passwords are left in place. Firefox history is removed with SQL so
# bookmarks, which share places.sqlite, stay.
#
# Refuses to touch a browser while that browser is running. --yes does not
# override that.
#
#   ./clear-browsers.sh --dry-run
#   ./clear-browsers.sh
#   ./clear-browsers.sh --yes
#   ./clear-browsers.sh --only chrome,firefox
#
# Not part of clear-all: clearing cookies signs you out of websites.
# Safari is macOS only.
set -euo pipefail

DRY_RUN=false
ASSUME_YES=false
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --yes|-y) ASSUME_YES=true ;;
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

confirm() {
  if [[ "$ASSUME_YES" == true ]]; then
    return 0
  fi
  local answer
  read -r -p "Clear history, cookies, and cache for the browsers listed above? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

OS="$(uname -s)"
case "$OS" in
  Linux|Darwin) ;;
  *) echo "This script supports macOS and Linux. On Windows run clear-browsers.ps1." >&2; exit 1 ;;
esac

if ! command -v pgrep >/dev/null 2>&1; then
  echo "pgrep is required so this script can refuse to run while a browser is open." >&2
  exit 1
fi

config_home() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
cache_home() { printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}"; }

# pgrep is inside `if` so a "not running" exit status does not abort under set -e.
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
  # pwd -P follows a directory symlink, so a cache dir that points outside
  # the home directory is refused instead of emptied.
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

# Chromium-family profile directories under a user-data root.
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

describe() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return 0
  fi
  local size
  size="$(du -sh "$path" 2>/dev/null | cut -f1)"
  echo "  $path  (${size:-unknown})"
}

queue_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  under_home "$path" || { echo "Skipping $path (outside your home directory)."; return 0; }
  ACTIONS+=("file|$path")
  describe "$path"
}

queue_dir() {
  local path="$1"
  [[ -d "$path" ]] || return 0
  under_home "$path" || { echo "Skipping $path (outside your home directory)."; return 0; }
  ACTIONS+=("dir|$path")
  describe "$path"
}

clear_firefox_history() {
  local db="$1"
  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3 is not installed, so Firefox history in $db was left untouched."
    echo "Cookies and cache for that profile are still cleared. Bookmarks were not deleted."
    return 0
  fi
  if ! sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table' AND name='moz_bookmarks';" | grep -q moz_bookmarks; then
    echo "Refusing to edit $db: it has no bookmark table, so it may not be a Firefox places database."
    return 0
  fi
  sqlite3 "$db" "DELETE FROM moz_historyvisits;"
  sqlite3 "$db" "DELETE FROM moz_inputhistory;" 2>/dev/null || true
  if sqlite3 "$db" "PRAGMA table_info(moz_places);" | grep -q foreign_count; then
    sqlite3 "$db" "DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL) AND (foreign_count = 0 OR foreign_count IS NULL);"
  else
    sqlite3 "$db" "DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL);"
  fi
  sqlite3 "$db" "VACUUM;" 2>/dev/null || true
}

queue_chromium() {
  local id="$1" label="$2" root="$3" cache_root="$4" profile
  echo "-- $label --"
  if [[ ! -d "$root" ]]; then
    echo "  Not installed ($root)."
    return 0
  fi
  if browser_running "$id"; then
    echo "  REFUSED: $label is running. Quit it and run this script again."
    REFUSED=1
    return 0
  fi
  local found=0
  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    found=1
    local base
    base="$(basename "$profile")"
    echo "  Profile: $profile"
    queue_file "$profile/History"
    queue_file "$profile/History-journal"
    queue_file "$profile/Cookies"
    queue_file "$profile/Cookies-journal"
    queue_file "$profile/Network/Cookies"
    queue_file "$profile/Network/Cookies-journal"
    queue_dir "$profile/Cache"
    queue_dir "$profile/Code Cache"
    queue_dir "$profile/GPUCache"
    queue_dir "$profile/Service Worker/CacheStorage"
    if [[ -n "$cache_root" ]]; then
      queue_dir "$cache_root/$base/Cache"
      queue_dir "$cache_root/$base/Code Cache"
      queue_dir "$cache_root/$base/GPUCache"
    fi
  done < <(chromium_profiles "$root")
  if [[ "$found" -eq 0 ]]; then
    echo "  No profiles under $root."
  fi
}

queue_firefox() {
  echo "-- Firefox --"
  if browser_running firefox; then
    echo "  REFUSED: Firefox is running. Quit it and run this script again."
    REFUSED=1
    return 0
  fi
  local found=0 profile
  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    [[ -d "$profile" ]] || continue
    if ! under_home "$profile"; then
      echo "Skipping $profile (outside your home directory)."
      continue
    fi
    found=1
    echo "  Profile: $profile"
    if [[ -f "$profile/places.sqlite" ]]; then
      ACTIONS+=("ff|$profile/places.sqlite")
      describe "$profile/places.sqlite"
      echo "    history rows only; bookmarks in this file are kept"
    fi
    queue_file "$profile/cookies.sqlite"
    queue_file "$profile/cookies.sqlite-wal"
    queue_file "$profile/cookies.sqlite-shm"
    queue_dir "$profile/cache2"
    queue_dir "$profile/startupCache"
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
    echo "  REFUSED: Safari is running. Quit it and run this script again."
    REFUSED=1
    return 0
  fi
  local found=0
  local paths=(
    "$HOME/Library/Safari/History.db"
    "$HOME/Library/Safari/History.db-wal"
    "$HOME/Library/Safari/History.db-shm"
    "$HOME/Library/Cookies/Cookies.binarycookies"
    "$HOME/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
  )
  local path
  for path in "${paths[@]}"; do
    if [[ -f "$path" ]]; then
      found=1
      queue_file "$path"
    fi
  done
  if [[ -d "$HOME/Library/Caches/com.apple.Safari" ]]; then
    found=1
    queue_dir "$HOME/Library/Caches/com.apple.Safari"
  fi
  if [[ -d "$HOME/Library/Containers/com.apple.Safari/Data/Library/Caches" ]]; then
    found=1
    queue_dir "$HOME/Library/Containers/com.apple.Safari/Data/Library/Caches"
  fi
  if [[ "$found" -eq 0 ]]; then
    echo "  No Safari history, cookies, or cache found."
  fi
  echo "  Bookmarks.plist is not touched."
}

ACTIONS=()
REFUSED=0

echo "== Browser history, cookies, and cache =="
echo "Bookmarks and saved passwords are not deleted."
echo

if want chrome; then
  if [[ "$OS" == "Darwin" ]]; then
    queue_chromium chrome "Chrome" "$HOME/Library/Application Support/Google/Chrome" "$HOME/Library/Caches/Google/Chrome"
  else
    queue_chromium chrome "Chrome" "$(config_home)/google-chrome" "$(cache_home)/google-chrome"
  fi
fi
if want chromium; then
  if [[ "$OS" == "Darwin" ]]; then
    queue_chromium chromium "Chromium" "$HOME/Library/Application Support/Chromium" "$HOME/Library/Caches/Chromium"
  else
    queue_chromium chromium "Chromium" "$(config_home)/chromium" "$(cache_home)/chromium"
  fi
fi
if want edge; then
  if [[ "$OS" == "Darwin" ]]; then
    queue_chromium edge "Edge" "$HOME/Library/Application Support/Microsoft Edge" "$HOME/Library/Caches/Microsoft Edge"
  else
    queue_chromium edge "Edge" "$(config_home)/microsoft-edge" "$(cache_home)/microsoft-edge"
  fi
fi
if want brave; then
  if [[ "$OS" == "Darwin" ]]; then
    queue_chromium brave "Brave" "$HOME/Library/Application Support/BraveSoftware/Brave-Browser" "$HOME/Library/Caches/BraveSoftware/Brave-Browser"
  else
    queue_chromium brave "Brave" "$(config_home)/BraveSoftware/Brave-Browser" "$(cache_home)/BraveSoftware/Brave-Browser"
  fi
fi
if want firefox; then
  queue_firefox
fi
if want safari; then
  queue_safari
fi

if [[ ${#ACTIONS[@]} -eq 0 ]]; then
  if [[ "$REFUSED" -eq 1 ]]; then
    echo "Nothing was cleared. At least one browser was open."
    exit 2
  fi
  echo "No browser history, cookies, or cache found for the selected browsers."
  exit 0
fi

if [[ "$REFUSED" -eq 1 ]]; then
  echo "Open browsers were skipped. The paths above are only the browsers that are closed."
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry run) Would clear ${#ACTIONS[@]} path(s). No change made."
  if [[ "$REFUSED" -eq 1 ]]; then
    exit 2
  fi
  exit 0
fi

confirm || { echo "Cancelled."; [[ "$REFUSED" -eq 1 ]] && exit 2; exit 0; }

for action in "${ACTIONS[@]}"; do
  kind="${action%%|*}"
  path="${action#*|}"
  case "$kind" in
    file)
      rm -f -- "$path"
      ;;
    dir)
      find "$path" -mindepth 1 -delete 2>/dev/null || true
      ;;
    ff)
      clear_firefox_history "$path"
      ;;
    *)
      echo "Internal error: $kind" >&2
      exit 1
      ;;
  esac
done

echo "Done. Closed browsers had history, cookies, and cache cleared."
echo "Local Storage and saved passwords were left alone, so a site might still recognize this profile until those are cleared in the browser."
if [[ "$REFUSED" -eq 1 ]]; then
  exit 2
fi
