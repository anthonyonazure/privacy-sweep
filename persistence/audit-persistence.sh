#!/usr/bin/env bash
# audit-persistence.sh - report-only persistence locations.
# macOS launch agents/daemons and login items. Linux user units, cron presence,
# and autostart desktop files. Never deletes. Does not print plist or unit contents.
#
#   ./audit-persistence.sh
#   PRIVACY_SWEEP_PERSIST_ROOT=/fixture ./audit-persistence.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=audit/report-lib.sh
source "$ROOT/audit/report-lib.sh"

for arg in "$@"; do
  case "$arg" in
    --dry-run|--yes|-y) ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

echo "== Persistence audit (report only; nothing deleted or unloaded) =="
echo "File contents, Exec= lines, and crontab commands are not printed."
echo

OS_NAME="${PRIVACY_SWEEP_OS:-$(uname -s)}"
root="${PRIVACY_SWEEP_PERSIST_ROOT:-}"

list_files() {
  local label="$1" path="$2" count listing
  echo "-- $label --"
  echo "Path: $path"
  if [[ ! -d "$path" ]]; then
    echo "Present: no"
    echo
    return 0
  fi
  # One line per basename. A second path with the same file name is not listed again.
  # -print keeps a carriage return that is part of the file name.
  listing="$(find -P "$path" -maxdepth 1 -type f -print 2>/dev/null | awk -F/ '!seen[$NF]++' || true)"
  if [[ -z "$listing" ]]; then
    count=0
  else
    count="$(printf '%s\n' "$listing" | wc -l | tr -d ' ')"
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
      [[ -n "$line" ]] || continue
      base="${line##*/}"
      if [[ "$base" == *[[:cntrl:]]* ]]; then
        # One \r in the escaped name is one real CR in the file name.
        # "name.plist\r" is a trailing CR. "name\r.plist\r" is a CR before
        # the extension and another at the end. Nothing is added here.
        # shellcheck disable=SC2016
        escaped="$(printf '%s' "$base" | perl -ne 's/\\/\\\\/g; s/\r/\\r/g; s/\n/\\n/g; s/\t/\\t/g; s/([\000-\037\177])/sprintf("\\x%02X", ord($1))/ge; chomp; print')"
        printf '  Suspicious name (control character): %s\n' "$escaped"
      else
        printf '  %s\n' "$line"
      fi
    done <<< "$listing"
  fi
  echo "Files: ${count:-0}"
  echo "Contents are not printed."
  echo
}

count_only() {
  local label="$1" path="$2" count
  echo "-- $label --"
  echo "Path: $path"
  if [[ ! -d "$path" ]]; then
    echo "Present: no"
    echo
    return 0
  fi
  count="$(find -P "$path" -maxdepth 1 -type f 2>/dev/null | awk -F/ '!seen[$NF]++' | wc -l | tr -d ' ' || true)"
  echo "Files: ${count:-0}"
  echo "Names are not listed (system directory)."
  echo
}

if [[ -n "$root" ]]; then
  list_files "LaunchAgents (user)" "$root/Library/LaunchAgents"
  list_files "LaunchDaemons (user)" "$root/Library/LaunchDaemons"
  list_files "systemd user units" "$root/systemd"
  list_files "autostart" "$root/autostart"
  if [[ -f "$root/loginitems.plist" ]]; then
    echo "-- Login items plist --"
    echo "Path: $root/loginitems.plist"
    echo "Present: yes"
    echo "Contents are not printed."
    echo
  else
    echo "-- Login items plist --"
    echo "Present: no"
    echo
  fi
else
  case "$OS_NAME" in
    Darwin)
      list_files "LaunchAgents (user)" "$HOME/Library/LaunchAgents"
      list_files "LaunchDaemons (user)" "$HOME/Library/LaunchDaemons"
      list_files "LaunchAgents (/Library)" "/Library/LaunchAgents"
      list_files "LaunchDaemons (/Library)" "/Library/LaunchDaemons"
      count_only "LaunchAgents (system)" "/System/Library/LaunchAgents"
      count_only "LaunchDaemons (system)" "/System/Library/LaunchDaemons"
      echo "-- Login items --"
      plist="$HOME/Library/Preferences/com.apple.loginitems.plist"
      echo "Path: $plist"
      if [[ -f "$plist" ]]; then
        echo "Present: yes"
        echo "Bytes: $(wc -c < "$plist" 2>/dev/null | tr -d ' ' || true)"
      else
        echo "Present: no"
      fi
      echo "The plist is not dumped."
      if command -v osascript >/dev/null 2>&1; then
        names="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || true)"
        if [[ -n "$names" ]]; then
          echo "Login item names:"
          printf '%s\n' "$names" | tr ',' '\n' | sed 's/^ */  /'
        else
          echo "Login item names from System Events: unavailable from this session."
        fi
      else
        echo "osascript is not available in this session."
      fi
      echo "-- Background items (macOS 13+) --"
      echo "sfltool dumpbtm is used only when it runs without sudo. This script does not use sudo."
      if command -v sfltool >/dev/null 2>&1; then
        dump=""
        run_bounded_capture dump sfltool dumpbtm
        if [[ "$SCAN_TIMED_OUT" -eq 1 ]]; then
          echo "sfltool dumpbtm did not finish. A GUI session may be required."
        else
          filtered="$(printf '%s\n' "$dump" | awk '/^[[:space:]]*(Name|Display Name|Bundle Identifier):/ { sub(/^[[:space:]]+/, ""); print "  " $0 }' || true)"
          if [[ -n "$filtered" ]]; then
            echo "Names from sfltool dumpbtm:"
            printf '%s\n' "$filtered"
            echo "Executable paths are not printed."
          else
            echo "sfltool dumpbtm returned no Name, Display Name, or Bundle Identifier lines without sudo."
            echo "On macOS 13+ a GUI session can list these. SSH often cannot. The raw dump is not printed."
          fi
        fi
      else
        echo "sfltool was not found. On macOS 13+ it lists background login items when a GUI session allows it."
      fi
      btm="$HOME/Library/Application Support/com.apple.backgroundtaskmanagementagent/backgrounditems.btm"
      echo "Path: $btm"
      if [[ -e "$btm" ]]; then
        echo "Present: yes (binary; not decoded)"
      else
        echo "Present: no"
      fi
      sysbtm="/private/var/db/com.apple.backgroundtaskmanagement"
      echo "Path: $sysbtm"
      if [[ -d "$sysbtm" ]]; then
        echo "Present: yes (not decoded)"
      else
        echo "Present: no"
      fi
      echo
      ;;
    Linux)
      list_files "systemd user units" "$HOME/.config/systemd/user"
      list_files "autostart (user)" "$HOME/.config/autostart"
      count_only "autostart (system xdg)" "/etc/xdg/autostart"
      echo "-- cron (presence only) --"
      if command -v crontab >/dev/null 2>&1; then
        cron_status=0
        cron_err="$(crontab -l 2>&1 >/dev/null)" || cron_status=$?
        if [[ "$cron_status" -eq 0 ]]; then
          echo "crontab -l: a crontab is installed (commands not printed)."
        elif [[ "$cron_err" == *"no crontab"* ]]; then
          echo "crontab -l: no crontab for this user."
        else
          echo "crontab -l: could not be checked from this account."
        fi
      else
        echo "crontab: not installed"
      fi
      if [[ -d /etc/cron.d ]]; then
        count="$(find -P /etc/cron.d -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
        echo "Files in /etc/cron.d: ${count:-0} (contents not printed)"
      fi
      echo
      ;;
    *)
      echo "This script supports macOS and Linux. On Windows run audit-persistence.ps1."
      exit 1
      ;;
  esac
fi

echo "Nothing was deleted, unloaded, or disabled."
echo "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
echo "Nothing was deleted."
