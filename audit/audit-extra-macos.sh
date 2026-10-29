#!/usr/bin/env bash
# audit-extra-macos.sh - part of privacy-sweep (report only)
# Second-tier macOS stores that the main audit does not cover: Messages,
# Bluetooth pairings, AirDrop and Screen Time settings, Siri and Apple
# Intelligence data, shell and tool history files beyond .zsh_history,
# SSH known_hosts, cloud CLI config folders, Docker, and install history.
# Prints presence, sizes, and line counts. Does not delete anything, does not
# print message text, device names, host names, commands, or credentials.
#
#   ./audit-extra-macos.sh
#   ./audit-extra-macos.sh --dry-run     # same report; there is nothing to apply
#
# Messages and some Library folders need Full Disk Access for the terminal. A
# store this account cannot read is reported as unreadable, not as empty.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
  case "$arg" in
    --dry-run|--yes|-y) ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

OS_NAME="${PRIVACY_SWEEP_OS:-$(uname -s)}"
if [[ "$OS_NAME" != "Darwin" ]]; then
  echo "This report is for macOS. Detected: $OS_NAME." >&2
  exit 1
fi

# shellcheck source=audit/report-lib.sh
source "$DIR/report-lib.sh"

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

echo "== macOS extra artifacts (counts and paths, nothing deleted) =="
echo "Report only. This does not clear these stores."
echo

echo "### Messages, Bluetooth, AirDrop, Screen Time"
echo "Message text, contact names, device names, and usage rows are not printed."
echo
MSG="$HOME/Library/Messages"
if [[ "$(user_dir_status "$MSG")" == "protected" ]]; then
  echo "-- Messages database --"
  echo "Path: $MSG"
  echo "Present: protected (grant Full Disk Access to this terminal to size it)"
  echo
else
  report_file_presence "Messages database (chat.db)" "$MSG/chat.db"
  report_file_presence "Messages database journal (chat.db-wal)" "$MSG/chat.db-wal"
  report_dir_summary "Messages attachments" "$MSG/Attachments"
fi
report_file_presence "Bluetooth pairings (system)" "/Library/Preferences/com.apple.Bluetooth.plist"
report_file_presence "Bluetooth settings (user)" "$HOME/Library/Preferences/com.apple.Bluetooth.plist"
report_file_presence "AirDrop and Sharing settings (sharingd)" "$HOME/Library/Preferences/com.apple.sharingd.plist"
report_file_presence "Screen Time agent settings" "$HOME/Library/Preferences/com.apple.ScreenTimeAgent.plist"
echo "AirDrop transfers also leave rows in the download log and in unified logs;"
echo "both are covered by the main audit. Screen Time usage rows live in knowledgeC."
echo

echo "### Siri, dictation, and Apple Intelligence"
report_protected_dir() {
  local label="$1" path="$2"
  if [[ "$(user_dir_status "$path")" == "protected" ]]; then
    echo "-- $label --"
    echo "Path: $path"
    echo "Present: protected (grant Full Disk Access to this terminal to size it)"
    echo
  else
    report_dir_summary "$label" "$path"
  fi
}
report_protected_dir "Siri assistant data" "$HOME/Library/Assistant"
report_protected_dir "Siri suggestions" "$HOME/Library/Suggestions"
report_protected_dir "Intelligence platform data" "$HOME/Library/IntelligencePlatform"
report_protected_dir "CoreSpotlight metadata" "$HOME/Library/Metadata/CoreSpotlight"
echo

echo "### Shell and tool history beyond .zsh_history"
report_dir_summary "Terminal session history (.zsh_sessions)" "$HOME/.zsh_sessions"
report_dir_summary "Terminal session history (.bash_sessions)" "$HOME/.bash_sessions"
report_lines "Vim history (.viminfo)" "$HOME/.viminfo"
report_lines "less history (.lesshst)" "$HOME/.lesshst"
report_lines "Python REPL history" "$HOME/.python_history"
report_lines "Node REPL history" "$HOME/.node_repl_history"
report_lines "MySQL client history" "$HOME/.mysql_history"
report_lines "psql history" "$HOME/.psql_history"
report_lines "sqlite3 history" "$HOME/.sqlite_history"
echo

echo "### Where you have connected, and developer tool state"
report_lines "SSH known_hosts (one line per host; names not printed)" "$HOME/.ssh/known_hosts"
report_dir_summary "AWS CLI config folder (credentials not read)" "$HOME/.aws"
report_dir_summary "Azure CLI config folder (tokens not read)" "$HOME/.azure"
report_dir_summary "Google Cloud CLI config folder (tokens not read)" "$HOME/.config/gcloud"
report_dir_summary "Docker config folder" "$HOME/.docker"
report_dir_summary "Docker Desktop container data" "$HOME/Library/Containers/com.docker.docker"
report_file_presence "macOS install history" "/Library/Receipts/InstallHistory.plist"
echo

echo "These stores are reported only. Nothing here is deleted by privacy-sweep."
echo "Messages, SSH known_hosts, and cloud CLI folders are account or identity data;"
echo "clear them yourself from the owning app if you want them gone."
