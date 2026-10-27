#!/usr/bin/env bash
# audit-local.sh - report-only counts and sizes for the stores in module I
# that live on macOS or Linux. Deletes nothing. Does not print file contents.
#
#   ./audit-local.sh
#   PRIVACY_SWEEP_HOME_ROOT=/fixture ./audit-local.sh
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

HOME_ROOT="${PRIVACY_SWEEP_HOME_ROOT:-$HOME}"
VOL_ROOT="${PRIVACY_SWEEP_VOLUME_ROOT:-/Volumes}"

echo "== Local artifacts (report only; nothing deleted) =="
echo "Mail stores are listed and are never deleted by privacy-sweep."
echo

report_if_dir() {
  report_dir_summary "$1" "$2"
}

# -xdev does not skip File Provider or TCC folders. These paths are pruned
# from every home-wide find. node_modules and .git are pruned by name.
HOME_PRUNE=()
desktop_status="$(user_dir_status "$HOME_ROOT/Desktop")"
documents_status="$(user_dir_status "$HOME_ROOT/Documents")"
downloads_status="$(user_dir_status "$HOME_ROOT/Downloads")"

setup_home_prune() {
  local p
  HOME_PRUNE=(
    -path "$HOME_ROOT/Library/CloudStorage" -o -path "$HOME_ROOT/Library/CloudStorage/*" -o
    -path "$HOME_ROOT/Library/Mobile Documents" -o -path "$HOME_ROOT/Library/Mobile Documents/*" -o
    -path "$HOME_ROOT/Library/Containers" -o -path "$HOME_ROOT/Library/Containers/*" -o
    -path "$HOME_ROOT/Library/Group Containers" -o -path "$HOME_ROOT/Library/Group Containers/*" -o
    -name node_modules -o -name .git
  )
  for p in Desktop Documents Downloads; do
    if [[ "$(user_dir_status "$HOME_ROOT/$p")" == "protected" ]]; then
      HOME_PRUNE+=( -o -path "$HOME_ROOT/$p" -o -path "$HOME_ROOT/$p/*" )
    fi
  done
}

home_find() {
  local depth="$1"
  shift
  find -P "$HOME_ROOT" -xdev -maxdepth "$depth" \
    \( "${HOME_PRUNE[@]}" \) -prune -o \
    -type f \( "$@" \) -print
}

count_text_lines() {
  local text="$1"
  if [[ -z "$text" ]]; then
    echo 0
  else
    printf '%s\n' "$text" | wc -l | tr -d ' '
  fi
}

echo "-- Desktop, Documents, and Downloads --"
echo "These folders are checked with a timed ls before any scan. macOS privacy protection can hide them from this session."
for pair in \
  "Desktop|$desktop_status|$HOME_ROOT/Desktop" \
  "Documents|$documents_status|$HOME_ROOT/Documents" \
  "Downloads|$downloads_status|$HOME_ROOT/Downloads"
do
  label="${pair%%|*}"
  rest="${pair#*|}"
  status="${rest%%|*}"
  path="${rest#*|}"
  echo "Path: $path"
  case "$status" in
    missing) echo "Present: no" ;;
    protected) echo "not readable from this session (macOS privacy protection)" ;;
    *) echo "Present: yes" ;;
  esac
  echo "Folder: $label"
done
echo

echo "-- Screenshots (counts only; file names can describe the screen) --"
for dir in "$HOME_ROOT/Pictures/Screenshots" "$HOME_ROOT/Pictures/screenshots" "$HOME_ROOT/Desktop"; do
  if [[ "$dir" == "$HOME_ROOT/Desktop" ]]; then
    echo "-- Desktop screenshot-like files --"
    echo "Path: $dir"
    case "$desktop_status" in
      missing)
        echo "Present: no"
        ;;
      protected)
        echo "not readable from this session (macOS privacy protection)"
        ;;
      *)
        shot_count=""
        # shellcheck disable=SC2016
        run_bounded_capture shot_count bash -c 'find -P "$1" -maxdepth 1 -type f \( -iname "Screenshot*" -o -iname "Screen Shot*" -o -iname "CleanShot*" \) 2>/dev/null | wc -l | tr -d " "' bash "$dir"
        if [[ "$SCAN_TIMED_OUT" -eq 1 ]]; then
          echo "Files: skipped"
        else
          shot_count="${shot_count//[^0-9]/}"
          echo "Files: ${shot_count:-0}"
        fi
        echo "Names are not listed."
        ;;
    esac
    echo
  else
    report_if_dir "Screenshots" "$dir"
  fi
done

echo "-- Clipboard managers (presence and size) --"
for pair in \
  "Klipper|$HOME_ROOT/.local/share/klipper" \
  "CopyQ|$HOME_ROOT/.local/share/copyq" \
  "GPaste|$HOME_ROOT/.local/share/gpaste" \
  "Maccy|$HOME_ROOT/Library/Containers/org.p0deje.Maccy" \
  "Paste|$HOME_ROOT/Library/Application Support/Paste" \
  "Parcellite|$HOME_ROOT/.local/share/parcellite"
do
  label="${pair%%|*}"
  path="${pair#*|}"
  report_if_dir "$label" "$path"
done
echo "Clipboard text is not printed."
echo

echo "-- Notification databases --"
report_if_dir "NotificationCenter" "$HOME_ROOT/Library/Application Support/NotificationCenter"
report_if_dir "usernoted" "$HOME_ROOT/Library/Group Containers/group.com.apple.usernoted"
report_if_dir "notifications" "$HOME_ROOT/.local/share/notifications"
echo

echo "-- .DS_Store count --"
if [[ -d "$HOME_ROOT" ]]; then
  setup_home_prune
  ds_list=""
  run_bounded_capture ds_list home_find 6 -name .DS_Store
  echo "Path: $HOME_ROOT"
  if [[ "$SCAN_TIMED_OUT" -eq 1 ]]; then
    echo "Files: skipped"
  else
    echo "Files: $(count_text_lines "$ds_list")"
  fi
  echo "Finder folder views are not printed."
  echo "CloudStorage, Mobile Documents, Containers, Group Containers, node_modules, and .git are not walked."
else
  echo "Home root is not a directory."
fi
echo

echo "-- Email stores (never deleted) --"
mail_count=0
mail_bytes=0
if [[ -d "$HOME_ROOT" ]]; then
  setup_home_prune
  mail_list=""
  run_bounded_capture mail_list home_find 5 -name '*.pst' -o -name '*.ost' -o -name '*.mbox'
  if [[ -n "$mail_list" ]]; then
    while IFS= read -r path || [[ -n "${path:-}" ]]; do
      [[ -n "$path" ]] || continue
      mail_count=$((mail_count + 1))
      size="$( { wc -c < "$path" | tr -d ' '; } 2>/dev/null )" || true
      if [[ "${size:-}" =~ ^[0-9]+$ ]]; then
        mail_bytes=$((mail_bytes + size))
      fi
      echo "Path: $path"
    done <<< "$mail_list"
  fi
fi
report_if_dir "Mail.app" "$HOME_ROOT/Library/Mail"
report_if_dir "Thunderbird" "$HOME_ROOT/.thunderbird"
report_if_dir "Thunderbird Library" "$HOME_ROOT/Library/Thunderbird"
echo "Loose PST/OST/MBOX files: $mail_count"
echo "Loose mail bytes: $mail_bytes"
echo "Message bodies are not read. These paths are not deleted."
echo

echo "-- Packet captures under the home directory --"
pcap_count=0
if [[ -d "$HOME_ROOT" ]]; then
  setup_home_prune
  pcap_list=""
  run_bounded_capture pcap_list home_find 4 -name '*.pcap' -o -name '*.pcapng' -o -name '*.cap'
  if [[ -n "$pcap_list" ]]; then
    while IFS= read -r path || [[ -n "${path:-}" ]]; do
      [[ -n "$path" ]] || continue
      pcap_count=$((pcap_count + 1))
      echo "Path: $(dirname "$path")"
    done <<< "$pcap_list"
  fi
fi
echo "Capture files: $pcap_count"
echo "Packet contents are not read. Captures are not deleted."
echo

echo "-- VM memory files under the home directory --"
vm_count=0
if [[ -d "$HOME_ROOT" ]]; then
  setup_home_prune
  vm_list=""
  run_bounded_capture vm_list home_find 5 -name '*.vmem' -o -name '*.vmss' -o -name '*.vmsn' -o -name '*.sav'
  if [[ -n "$vm_list" ]]; then
    while IFS= read -r path || [[ -n "${path:-}" ]]; do
      [[ -n "$path" ]] || continue
      vm_count=$((vm_count + 1))
      echo "Path: $(dirname "$path")"
    done <<< "$vm_list"
  fi
fi
echo "VM memory files: $vm_count"
echo "Guest RAM contents are not read. These files are not deleted."
echo

echo "-- Password manager presence (never extracted) --"
report_if_dir "1Password" "$HOME_ROOT/Library/Group Containers/2BUA8C4S2C.com.1password"
report_if_dir "Bitwarden" "$HOME_ROOT/.config/Bitwarden"
report_file_presence "Bitwarden data" "$HOME_ROOT/.config/Bitwarden/data.json"
echo "Vault contents, keys, and passwords are out of scope and are not read."
echo

echo "-- TCC.db (presence only; never modified) --"
for tcc in \
  "$HOME_ROOT/Library/Application Support/com.apple.TCC/TCC.db" \
  "/Library/Application Support/com.apple.TCC/TCC.db"
do
  report_file_presence "TCC.db" "$tcc"
  if [[ -r "$tcc" ]] && command -v sqlite3 >/dev/null 2>&1; then
    rows="$(sqlite3 "$tcc" "SELECT COUNT(*) FROM access;" 2>/dev/null || true)"
    if [[ -n "$rows" ]]; then
      echo "access rows: $rows"
      echo "Client, service, and prompt rows are not printed."
    fi
  fi
done
echo "This script does not UPDATE, DELETE, or INSERT into TCC.db."
echo

echo "-- Spotlight index (size only) --"
report_if_dir "Spotlight" "/.Spotlight-V100"
report_if_dir "Spotlight Data" "/System/Volumes/Data/.Spotlight-V100"
echo "To keep a volume out of the index, a .metadata_never_index file is a setting, documented in docs/reduce-future-logging.md. This script does not create it."
echo

echo "-- External volumes (Trash and Spotlight), when mounted --"
if [[ -d "$VOL_ROOT" ]]; then
  shopt -s nullglob
  trashes=("$VOL_ROOT"/*/.Trashes)
  spots=("$VOL_ROOT"/*/.Spotlight-V100)
  shopt -u nullglob
  if [[ ${#trashes[@]} -eq 0 ]]; then
    echo "No .Trashes under $VOL_ROOT"
  else
    for trash in "${trashes[@]}"; do
      report_if_dir "External .Trashes" "$trash"
    done
  fi
  if [[ ${#spots[@]} -eq 0 ]]; then
    echo "No .Spotlight-V100 under $VOL_ROOT"
  else
    for spot in "${spots[@]}"; do
      report_if_dir "External Spotlight" "$spot"
    done
  fi
else
  echo "Path: $VOL_ROOT"
  echo "Present: no"
fi
echo

echo "-- auditd --"
report_file_presence "audit.log" "/var/log/audit/audit.log"
echo "Opt-in vacuum is separate (--vacuum-auditd) and is not part of clear-all."
echo "systemd journal forward-secure sealing can show that a journal was rewritten. See docs/anti-forensics.md."
echo

echo "-- Finder preferences (size only) --"
report_file_presence "Finder plist" "$HOME_ROOT/Library/Preferences/com.apple.finder.plist"
echo "Preference keys are not printed."
echo

echo "-- Advisories that this script does not automate --"
echo "ARP and DHCP leases are volatile. The router holds the longer copy. See docs/leave-no-trace.md."
echo "DNS client cache is volatile. Flush is opt-in in clear-local.sh / clear-local.ps1."
echo "MFT and \$UsnJrnl are not modified. Userspace mutilation of those structures is out of scope."
echo "USBSTOR is not deleted. Keychain and password-vault extraction are out of scope."
echo "Event Log mass wipe is not the default. Channel sizes are the Windows audit in audit-local.ps1."
echo

echo "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
echo "Nothing was deleted."
