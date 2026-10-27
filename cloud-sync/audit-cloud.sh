#!/usr/bin/env bash
# audit-cloud.sh - presence and size of local cloud-sync logs and databases.
# Deletes nothing. Does not print file contents or tokens.
#
#   ./audit-cloud.sh
#   PRIVACY_SWEEP_CLOUD_ROOT=/fixture ./audit-cloud.sh
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

echo "== Cloud sync metadata (report only; nothing deleted) =="
echo "Clearing a local cache does not clear the account, its versions, its device list, or its activity log."
echo "See cloud-sync/README.md for the per-service checklist."
echo

OS_NAME="${PRIVACY_SWEEP_OS:-$(uname -s)}"
base="${PRIVACY_SWEEP_CLOUD_ROOT:-}"

report_one() {
  report_dir_summary "$1" "$2"
}

if [[ -n "$base" ]]; then
  report_one "OneDrive logs" "$base/OneDrive/logs"
  report_file_presence "OneDrive SyncEngineDatabase.db" "$base/OneDrive/SyncEngineDatabase.db"
  report_one "iCloud CloudDocs" "$base/CloudDocs"
  report_one "Dropbox instance db" "$base/Dropbox/instance_db"
  report_file_presence "Dropbox host.db" "$base/Dropbox/host.db"
  report_one "Google DriveFS" "$base/DriveFS"
else
  case "$OS_NAME" in
    Darwin)
      report_one "iCloud Mobile Documents" "$HOME/Library/Mobile Documents"
      report_one "iCloud CloudDocs" "$HOME/Library/Application Support/CloudDocs"
      report_one "Dropbox support" "$HOME/Library/Application Support/Dropbox"
      report_one "Dropbox dot-folder" "$HOME/.dropbox"
      report_one "Google DriveFS" "$HOME/Library/Application Support/Google/DriveFS"
      report_one "OneDrive CloudStorage" "$HOME/Library/CloudStorage"
      ;;
    Linux)
      report_one "Dropbox dot-folder" "$HOME/.dropbox"
      report_one "Dropbox cache" "$HOME/Dropbox/.dropbox.cache"
      report_one "OneDrive config" "$HOME/.config/onedrive"
      report_one "Google Drive config" "$HOME/.config/google-drive-ocamlfuse"
      report_one "Google Drive gdfuse" "$HOME/.gdfuse"
      ;;
    *)
      echo "This script supports macOS and Linux. On Windows run audit-cloud.ps1."
      exit 1
      ;;
  esac
fi

echo "Names inside these stores are not listed. Tokens and file contents are not printed."
echo "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
echo "Nothing was deleted."
echo "The cloud copy, version history, device list, and activity log are unchanged."
