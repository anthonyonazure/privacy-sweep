#!/usr/bin/env bash
# audit-persistence.sh - report-only persistence locations.
# macOS launch agents/daemons and login items. Linux user units, cron presence,
# and autostart desktop files. Never deletes. Does not print plist or unit contents.
#
#   ./audit-persistence.sh
#   PRIVACY_SWEEP_PERSIST_ROOT=/fixture ./audit-persistence.sh
set -euo pipefail

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
  local label="$1" path="$2" count
  echo "-- $label --"
  echo "Path: $path"
  if [[ ! -d "$path" ]]; then
    echo "Present: no"
    echo
    return 0
  fi
  count="$(find -P "$path" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
  echo "Files: ${count:-0}"
  find -P "$path" -maxdepth 1 -type f 2>/dev/null | sed 's/^/  /' || true
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
  count="$(find -P "$path" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
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
          echo "Login item names: unavailable from this session."
        fi
      fi
      btm="$HOME/Library/Application Support/com.apple.backgroundtaskmanagementagent/backgrounditems.btm"
      echo "Path: $btm"
      if [[ -e "$btm" ]]; then
        echo "Present: yes (binary; not decoded)"
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
