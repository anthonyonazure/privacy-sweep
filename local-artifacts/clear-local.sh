#!/usr/bin/env bash
# clear-local.sh - opt-in clears for screenshots, clipboard managers,
# notification DBs, .DS_Store, external Trash, and DNS cache.
# Dry-run unless --apply. --yes does not delete. Mail is never deleted.
# Not part of clear-all.
#
#   ./clear-local.sh --dry-run --all-opt-in
#   ./clear-local.sh --clear-screenshots --apply
#   ./clear-local.sh --vacuum-auditd --apply
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=lib/confirm.sh
source "$ROOT/lib/confirm.sh"

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
    */Pictures/Screenshots|*/Pictures/screenshots|*/.local/share/klipper|*/.local/share/copyq|*/.local/share/gpaste|*/.local/share/parcellite|*/Library/Application\ Support/NotificationCenter|*/.local/share/notifications|*/.Trashes|*/.Trashes/*)
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
  n="$(find -P "$HOME_ROOT" -xdev -maxdepth 6 -name .DS_Store -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
  echo "Files: ${n:-0}"
  if will_apply; then
    find -P "$HOME_ROOT" -xdev -maxdepth 6 -name .DS_Store -type f -delete 2>/dev/null || true
    echo "Deleted .DS_Store files under $HOME_ROOT (max depth 6). Finder will recreate them."
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

if [[ "$DO_SHOTS" != true && "$DO_CLIP" != true && "$DO_NOTE" != true && "$DO_DS" != true && "$DO_DNS" != true && "$DO_TRASH" != true && "$DO_AUDITD" != true ]]; then
  echo "No clear flag was set. Pass --all-opt-in or a specific --clear-* flag."
fi

if ! will_apply; then
  echo "Dry run: nothing was deleted."
fi
echo "Mail was not deleted."
