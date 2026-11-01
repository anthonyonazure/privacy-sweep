#!/usr/bin/env bash
# clear-local.sh - opt-in clears for screenshots, clipboard managers,
# notification DBs, .DS_Store, external Trash, and DNS cache.
# Dry-run unless --apply. --yes does not delete. Mail is never deleted.
# Not part of clear-all.
#
#   ./clear-local.sh --dry-run --all-opt-in
#   ./clear-local.sh --clear-screenshots --apply
#   ./clear-local.sh --clear-tool-history --apply   # .viminfo, .lesshst, REPL and DB-client history
#   ./clear-local.sh --clear-crash-dumps --apply    # Linux /var/crash and systemd core dumps (root)
#   ./clear-local.sh --clear-device-backups --apply # iPhone/iPad backups; typed phrase; not in --all-opt-in
#   ./clear-local.sh --vacuum-auditd --apply
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=lib/confirm.sh
source "$ROOT/lib/confirm.sh"
# shellcheck source=audit/report-lib.sh
source "$ROOT/audit/report-lib.sh"

DRY_RUN=false
APPLY=false
ALL=false
DO_SHOTS=false
DO_CLIP=false
DO_NOTE=false
DO_DS=false
DO_DNS=false
DO_TRASH=false
DO_AUDITD=false
DO_TOOLS=false
DO_DUMPS=false
DO_BACKUPS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --apply) APPLY=true ;;
    --yes|-y) ;;
    --all-opt-in) ALL=true ;;
    --clear-screenshots) DO_SHOTS=true ;;
    --clear-clipboard-managers) DO_CLIP=true ;;
    --clear-notifications) DO_NOTE=true ;;
    --clear-ds-store) DO_DS=true ;;
    --flush-dns) DO_DNS=true ;;
    --clear-external-trash) DO_TRASH=true ;;
    --vacuum-auditd) DO_AUDITD=true ;;
    --clear-tool-history) DO_TOOLS=true ;;
    --clear-crash-dumps) DO_DUMPS=true ;;
    --clear-device-backups) DO_BACKUPS=true ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ "$ALL" == true ]]; then
  DO_SHOTS=true
  DO_CLIP=true
  DO_NOTE=true
  DO_DS=true
  DO_DNS=true
  DO_TRASH=true
  DO_TOOLS=true
  DO_DUMPS=true
fi

HOME_ROOT="${PRIVACY_SWEEP_HOME_ROOT:-$HOME}"
VOL_ROOT="${PRIVACY_SWEEP_VOLUME_ROOT:-/Volumes}"

echo "== Local artifact clears (opt-in) =="
echo "Mail stores, message databases, and bookmarks are not on this list."
echo "Nothing is deleted unless you pass --apply. --yes does not delete."
echo "This is not part of clear-all."
echo

will_apply() {
  [[ "$APPLY" == true && "$DRY_RUN" != true ]]
}

count_files() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    echo 0
    return 0
  fi
  find -P "$path" -type f 2>/dev/null | wc -l | tr -d ' ' || true
}

clear_dir_contents() {
  local path="$1"
  case "$path" in
    */Pictures/Screenshots|*/Pictures/screenshots|*/.local/share/klipper|*/.local/share/copyq|*/.local/share/gpaste|*/.local/share/parcellite|*/Library/Application\ Support/NotificationCenter|*/.local/share/notifications|*/.Trashes|*/.Trashes/*|*/.zsh_sessions|*/.bash_sessions)
      ;;
    *)
      echo "Refusing unexpected path: $path"
      return 0
      ;;
  esac
  local n
  n="$(count_files "$path")"
  echo "Path: $path  Files: ${n:-0}"
  if will_apply; then
    find -P "$path" -mindepth 1 -delete 2>/dev/null || true
    echo "Cleared contents of $path"
  else
    echo "Dry run: would clear contents. Nothing was deleted."
  fi
}

if [[ "$DO_SHOTS" == true ]]; then
  echo "-- Screenshots --"
  for dir in "$HOME_ROOT/Pictures/Screenshots" "$HOME_ROOT/Pictures/screenshots"; do
    if [[ -d "$dir" ]]; then
      clear_dir_contents "$dir"
    else
      echo "Not present: $dir"
    fi
  done
  desk="$HOME_ROOT/Desktop"
  if [[ -d "$desk" ]]; then
    n="$(find -P "$desk" -maxdepth 1 -type f \( -iname 'Screenshot*' -o -iname 'Screen Shot*' -o -iname 'CleanShot*' \) 2>/dev/null | wc -l | tr -d ' ' || true)"
    echo "Desktop screenshot-like files: ${n:-0} (names not listed)"
    if will_apply; then
      find -P "$desk" -maxdepth 1 -type f \( -iname 'Screenshot*' -o -iname 'Screen Shot*' -o -iname 'CleanShot*' \) -delete 2>/dev/null || true
      echo "Deleted those Desktop files. Other Desktop files were left."
    else
      echo "Dry run: other Desktop files would be left."
    fi
  fi
  echo
fi

if [[ "$DO_CLIP" == true ]]; then
  echo "-- Clipboard managers --"
  for dir in \
    "$HOME_ROOT/.local/share/klipper" \
    "$HOME_ROOT/.local/share/copyq" \
    "$HOME_ROOT/.local/share/gpaste" \
    "$HOME_ROOT/.local/share/parcellite"
  do
    if [[ -d "$dir" ]]; then
      clear_dir_contents "$dir"
    else
      echo "Not present: $dir"
    fi
  done
  echo "Clipboard text is not printed."
  echo
fi

if [[ "$DO_NOTE" == true ]]; then
  echo "-- Notification databases --"
  for dir in \
    "$HOME_ROOT/Library/Application Support/NotificationCenter" \
    "$HOME_ROOT/.local/share/notifications"
  do
    if [[ -d "$dir" ]]; then
      clear_dir_contents "$dir"
    else
      echo "Not present: $dir"
    fi
  done
  echo
fi

if [[ "$DO_DS" == true ]]; then
  echo "-- .DS_Store --"
  setup_home_prune
  ds_list=""
  capture_home_find ds_list 6 -name .DS_Store
  if [[ "$SCAN_TIMED_OUT" -eq 1 ]]; then
    echo "Files: skipped"
  else
    echo "Files: $(count_text_lines "$ds_list")"
  fi
  echo "Library, CloudStorage, Mobile Documents, Containers, Group Containers, node_modules, and .git are not walked."
  if will_apply && [[ "$SCAN_TIMED_OUT" -eq 1 ]]; then
    echo "Scan timed out. Listed .DS_Store files were not deleted."
  elif will_apply && [[ -n "$ds_list" ]]; then
    while IFS= read -r ds_path || [[ -n "${ds_path:-}" ]]; do
      [[ -n "$ds_path" ]] || continue
      case "$ds_path" in
        "$HOME_ROOT"/.DS_Store|"$HOME_ROOT"/*) ;;
        *)
          echo "Refusing unexpected path."
          continue
          ;;
      esac
      command rm -f -- "$ds_path"
    done <<< "$ds_list"
    echo "Deleted listed .DS_Store files under $HOME_ROOT (max depth 6). Finder will recreate them."
  elif will_apply; then
    echo "No .DS_Store files to delete."
  else
    echo "Dry run: nothing was deleted."
  fi
  echo
fi

if [[ "$DO_DNS" == true ]]; then
  echo "-- DNS cache flush --"
  echo "The local resolver cache is volatile. The router still has its own log."
  OS_NAME="${PRIVACY_SWEEP_OS:-$(uname -s)}"
  if [[ "$OS_NAME" == "Darwin" ]]; then
    echo "Would run: dscacheutil -flushcache"
    echo "Would run: killall -HUP mDNSResponder"
  else
    echo "Would run: resolvectl flush-caches"
  fi
  if will_apply; then
    if [[ -n "${PRIVACY_SWEEP_DNS_LOG:-}" ]]; then
      printf '%s\n' 'flush-dns' >> "$PRIVACY_SWEEP_DNS_LOG"
      echo "SIMULATION: DNS cache was not flushed."
    elif [[ "$OS_NAME" == "Darwin" ]]; then
      dscacheutil -flushcache 2>/dev/null || true
      killall -HUP mDNSResponder 2>/dev/null || true
      echo "Flush requested."
    elif command -v resolvectl >/dev/null 2>&1; then
      resolvectl flush-caches 2>/dev/null || echo "resolvectl failed. Nothing else was changed."
    else
      echo "resolvectl was not found. Nothing was flushed."
    fi
  else
    echo "Dry run: nothing was flushed."
  fi
  echo
fi

if [[ "$DO_TRASH" == true ]]; then
  echo "-- External volume Trash --"
  if [[ -d "$VOL_ROOT" ]]; then
    shopt -s nullglob
    trashes=("$VOL_ROOT"/*/.Trashes)
    shopt -u nullglob
    if [[ ${#trashes[@]} -eq 0 ]]; then
      echo "No .Trashes under $VOL_ROOT"
    else
      for trash in "${trashes[@]}"; do
        clear_dir_contents "$trash"
      done
    fi
  else
    echo "Not present: $VOL_ROOT"
  fi
  echo
fi

if [[ "$DO_TOOLS" == true ]]; then
  echo "-- Tool history files --"
  echo "Editor, pager, REPL, and database-client history. Each app recreates its file."
  echo "Shell history (.zsh_history, .bash_history) has its own per-OS clear script."
  echo "A shell that is still open rewrites its session file when it exits."
  for name in .viminfo .lesshst .python_history .node_repl_history .mysql_history .psql_history .sqlite_history; do
    file="$HOME_ROOT/$name"
    if [[ -f "$file" ]]; then
      n="$(wc -l < "$file" 2>/dev/null | tr -d ' ' || true)"
      echo "Path: $file  Lines: ${n:-unreadable} (contents not printed)"
      if will_apply; then
        command rm -f -- "$file"
        echo "Deleted $file"
      else
        echo "Dry run: would delete. Nothing was deleted."
      fi
    else
      echo "Not present: $file"
    fi
  done
  for dir in "$HOME_ROOT/.zsh_sessions" "$HOME_ROOT/.bash_sessions"; do
    if [[ -d "$dir" ]]; then
      clear_dir_contents "$dir"
    else
      echo "Not present: $dir"
    fi
  done
  echo
fi

dump_dir_allowed() {
  case "$1" in
    /var/crash|/var/lib/systemd/coredump) return 0 ;;
  esac
  [[ -n "${PRIVACY_SWEEP_CRASH_DIR:-}" && "$1" == "$PRIVACY_SWEEP_CRASH_DIR" ]] && return 0
  [[ -n "${PRIVACY_SWEEP_COREDUMP_DIR:-}" && "$1" == "$PRIVACY_SWEEP_COREDUMP_DIR" ]] && return 0
  return 1
}

if [[ "$DO_DUMPS" == true ]]; then
  echo "-- Crash dumps and core dumps (Linux) --"
  echo "Apport and kdump files and systemd core dumps can hold a copy of process or kernel memory."
  echo "They are only written again if something crashes. File contents are not printed."
  CRASH_DIR="${PRIVACY_SWEEP_CRASH_DIR:-/var/crash}"
  CORE_DIR="${PRIVACY_SWEEP_COREDUMP_DIR:-/var/lib/systemd/coredump}"
  for dir in "$CRASH_DIR" "$CORE_DIR"; do
    if ! dump_dir_allowed "$dir"; then
      echo "Refusing unexpected path: $dir"
      continue
    fi
    if [[ ! -d "$dir" ]]; then
      echo "Not present: $dir"
      continue
    fi
    echo "Path: $dir  Files: $(count_files "$dir") (as seen by this account)"
    if will_apply; then
      if [[ -z "${PRIVACY_SWEEP_CRASH_DIR:-}${PRIVACY_SWEEP_COREDUMP_DIR:-}" && "$(id -u)" -ne 0 ]]; then
        echo "Refusing: these folders are root-only. Nothing was changed."
        continue
      fi
      find -P "$dir" -mindepth 1 -delete 2>/dev/null || true
      left="$(count_files "$dir")"
      if [[ "${left:-0}" -eq 0 ]]; then
        echo "Cleared contents of $dir"
      else
        echo "Could not delete everything in $dir. Files left: $left"
      fi
    else
      echo "Dry run: would clear contents. Nothing was deleted."
    fi
  done
  echo
fi

if [[ "$DO_BACKUPS" == true ]]; then
  echo "-- iPhone and iPad backups --"
  echo "WARNING: each backup is a full copy of a device. If it is your only copy, it cannot be recovered."
  echo "This is not part of --all-opt-in. Backup folder names are not listed."
  backup_root="$HOME_ROOT/Library/Application Support/MobileSync/Backup"
  case "$backup_root" in
    */MobileSync/Backup) ;;
    *) echo "Refusing unexpected path."; backup_root="" ;;
  esac
  if [[ -z "$backup_root" ]]; then
    :
  elif [[ ! -d "$backup_root" ]]; then
    echo "Not present: $backup_root"
  elif [[ "$(user_dir_status "$backup_root")" == "protected" ]]; then
    echo "Path: $backup_root"
    echo "Present: protected (grant Full Disk Access to this terminal to count or delete it). Nothing was changed."
  else
    n_backups="$(find -P "$backup_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || true)"
    echo "Path: $backup_root  Backups: ${n_backups:-0}  Files: $(count_files "$backup_root")"
    if will_apply; then
      if [[ "${n_backups:-0}" -eq 0 ]]; then
        echo "No backups to delete."
      elif confirm_phrase "DELETE DEVICE BACKUPS"; then
        find -P "$backup_root" -mindepth 1 -delete 2>/dev/null || true
        left="$(count_files "$backup_root")"
        if [[ "${left:-0}" -eq 0 ]]; then
          echo "Deleted the contents of $backup_root"
        else
          echo "Could not delete everything in $backup_root. Files left: $left"
        fi
      fi
    else
      echo "Dry run: would delete after you type a confirmation phrase. Nothing was deleted."
    fi
  fi
  echo
fi

if [[ "$DO_AUDITD" == true ]]; then
  echo "-- auditd vacuum --"
  echo "WARNING: this discards a syscall audit trail. Forward-secure journal sealing can show other log tampering. See docs/anti-forensics.md."
  echo "Would rotate /var/log/audit if you confirm and this account may do so."
  if will_apply; then
    if confirm_phrase "VACUUM AUDIT LOGS"; then
      if [[ -n "${PRIVACY_SWEEP_AUDITD_LOG:-}" ]]; then
        printf '%s\n' 'vacuum-auditd' >> "$PRIVACY_SWEEP_AUDITD_LOG"
        echo "SIMULATION: audit logs were not rotated."
      elif [[ "$(id -u)" -ne 0 ]]; then
        echo "Refusing: auditd vacuum needs root. Nothing was changed."
      else
        service auditd rotate 2>/dev/null || systemctl kill --signal SIGUSR1 auditd 2>/dev/null || echo "Could not signal auditd. Nothing else was deleted."
      fi
    fi
  else
    echo "Dry run: nothing was rotated."
  fi
  echo
fi

if [[ "$DO_SHOTS" != true && "$DO_CLIP" != true && "$DO_NOTE" != true && "$DO_DS" != true && "$DO_DNS" != true && "$DO_TRASH" != true && "$DO_AUDITD" != true && "$DO_TOOLS" != true && "$DO_DUMPS" != true && "$DO_BACKUPS" != true ]]; then
  echo "No clear flag was set. Pass --all-opt-in or a specific --clear-* flag."
fi

if ! will_apply; then
  echo "Dry run: nothing was deleted."
fi
echo "Mail was not deleted."
