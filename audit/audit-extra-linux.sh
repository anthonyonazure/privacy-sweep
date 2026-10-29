#!/usr/bin/env bash
# audit-extra-linux.sh - part of privacy-sweep (report only)
# Second-tier Linux stores that the main audit does not cover: package manager
# logs, Flatpak and Snap app data, USB connection events, Bluetooth pairings,
# saved Wi-Fi profiles, desktop keyrings, location service data, SSH
# known_hosts, remote-desktop clients, and tool history files.
# Prints presence, sizes, and counts. Does not delete anything, does not print
# package names, device serials, network names, host names, or commands.
#
#   ./audit-extra-linux.sh
#   ./audit-extra-linux.sh --dry-run     # same report; there is nothing to apply
#
# Several of these live under /var or /etc and are root-only. A store this
# account cannot read is reported as unreadable, not as empty.
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

# shellcheck source=audit/report-lib.sh
source "$DIR/report-lib.sh"

XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONF="${XDG_CONFIG_HOME:-$HOME/.config}"

# Line count for a text file. Contents are never printed.
report_lines() {
  local label="$1" path="$2" n=""
  echo "-- $label --"
  echo "Path: $path"
  if [[ ! -e "$path" ]]; then
    echo "Present: no"
    echo
    return 0
  fi
  if n="$(wc -l <"$path" 2>/dev/null)"; then
    echo "Present: yes"
    echo "Lines: ${n//[^0-9]/}"
  else
    echo "Present: yes (unreadable from this account)"
  fi
  echo "Contents are not printed."
  echo
}

# Directory that may be root-only: say so instead of reporting zero.
report_dir_guarded() {
  local label="$1" path="$2"
  if [[ -d "$path" && ! -r "$path" ]]; then
    echo "-- $label --"
    echo "Path: $path"
    echo "Present: yes (unreadable from this account; run as root to size it)"
    echo
    return 0
  fi
  report_dir_summary "$label" "$path"
}

# Count of lines matching a pattern in one log. Matching lines are not printed.
report_match_count() {
  local label="$1" path="$2" pattern="$3" n=""
  echo "-- $label --"
  echo "Path: $path"
  if [[ ! -e "$path" ]]; then
    echo "Present: no"
    echo
    return 0
  fi
  if n="$(grep -c -E "$pattern" "$path" 2>/dev/null)"; then
    echo "Matches: ${n//[^0-9]/}"
  elif [[ -r "$path" ]]; then
    echo "Matches: 0"
  else
    echo "Present: yes (unreadable from this account)"
  fi
  echo "Matching lines are not printed."
  echo
}

echo "== Linux extra artifacts (counts and paths, nothing deleted) =="
echo "Report only. This does not clear these stores."
echo

echo "### Package manager history (what was installed, and when)"
echo "Package names are not printed."
echo
report_file_presence "apt history" "/var/log/apt/history.log"
report_file_presence "apt terminal log" "/var/log/apt/term.log"
report_file_presence "dpkg log" "/var/log/dpkg.log"
report_file_presence "dnf log" "/var/log/dnf.log"
report_file_presence "yum log" "/var/log/yum.log"
report_file_presence "zypper history" "/var/log/zypp/history"
report_file_presence "pacman log" "/var/log/pacman.log"
report_dir_summary "Flatpak user apps and data" "$HOME/.var/app"
report_dir_summary "Snap user data" "$HOME/snap"
echo

echo "### USB connection events"
echo "Device serials and names are not printed; only how many connect events exist."
echo
report_match_count "USB connects in kern.log" "/var/log/kern.log" "New USB device found"
report_match_count "USB connects in syslog" "/var/log/syslog" "New USB device found"
report_match_count "USB connects in messages" "/var/log/messages" "New USB device found"
echo

echo "### Bluetooth, Wi-Fi, and location"
report_dir_guarded "Bluetooth paired devices (root-only)" "/var/lib/bluetooth"
report_dir_guarded "NetworkManager saved connections (root-only)" "/etc/NetworkManager/system-connections"
report_dir_guarded "GeoClue location service data" "/var/lib/geoclue"
echo

echo "### Desktop keyrings (contents never read)"
report_dir_summary "GNOME Keyring files" "$XDG_DATA/keyrings"
report_dir_summary "KDE Wallet files" "$XDG_DATA/kwalletd"
echo

echo "### Where you have connected, and tool history"
report_lines "SSH known_hosts (one line per host; names not printed)" "$HOME/.ssh/known_hosts"
report_dir_summary "Remmina remote-desktop profiles" "$XDG_DATA/remmina"
report_dir_summary "FreeRDP known hosts" "$XDG_CONF/freerdp"
report_lines "Vim history (.viminfo)" "$HOME/.viminfo"
report_lines "less history (.lesshst)" "$HOME/.lesshst"
report_lines "Python REPL history" "$HOME/.python_history"
report_lines "MySQL client history" "$HOME/.mysql_history"
report_lines "psql history" "$HOME/.psql_history"
report_dir_summary "Docker user config" "$HOME/.docker"
report_dir_guarded "Docker engine data (root-only)" "/var/lib/docker"
report_dir_summary "AWS CLI config folder (credentials not read)" "$HOME/.aws"
report_dir_summary "Azure CLI config folder (tokens not read)" "$HOME/.azure"
report_dir_summary "Google Cloud CLI config folder (tokens not read)" "$XDG_CONF/gcloud"
echo

echo "These stores are reported only. Nothing here is deleted by privacy-sweep."
echo "Keyrings, SSH known_hosts, and cloud CLI folders are identity data;"
echo "clear them yourself from the owning app if you want them gone."
