#!/usr/bin/env bash
# purge-macos.sh - opt-in delete of APFS local snapshots and Document Revisions.
# Dry-run unless --apply. --yes does not delete and does not skip the typed phrase.
# Not part of clear-all.
#
#   ./purge-macos.sh
#   ./purge-macos.sh --dry-run --purge-apfs-localsnapshots
#   ./purge-macos.sh --purge-apfs-localsnapshots --apply
#   ./purge-macos.sh --purge-document-revisions --apply
#
# Phrases: DELETE LOCAL SNAPSHOTS
#          DELETE DOCUMENT REVISIONS
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=lib/confirm.sh
source "$ROOT/lib/confirm.sh"

DRY_RUN=false
APPLY=false
PURGE_SNAP=false
PURGE_REV=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --apply) APPLY=true ;;
    --yes|-y) ;;
    --purge-apfs-localsnapshots) PURGE_SNAP=true ;;
    --purge-document-revisions) PURGE_REV=true ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

OS_NAME="${PRIVACY_SWEEP_OS:-$(uname -s)}"
if [[ -z "${PRIVACY_SWEEP_RECOVERY_ROOT:-}" && "$OS_NAME" != "Darwin" ]]; then
  echo "APFS snapshots and Document Revisions are a macOS store. Detected: $OS_NAME." >&2
  echo "Nothing was deleted." >&2
  exit 1
fi

cat <<'EOF'
WARNING: this destroys your backups / Previous Versions / ransomware recovery.
Local APFS snapshots and Document Revisions are how a Mac rolls a file back.
They are not a cache. Deleting them throws away that rollback copy.
Ransomware recovery often depends on snapshots like these.
Nothing is deleted unless you pass --apply and type the confirmation phrase.
--yes does not delete. This is not part of clear-all.
EOF
echo

echo "-- What the recovery audit found --"
bash "$ROOT/audit/audit-recovery-macos.sh" --dry-run
echo

if [[ "$PURGE_SNAP" != true && "$PURGE_REV" != true ]]; then
  echo "No purge flag was set. Pass --purge-apfs-localsnapshots and/or --purge-document-revisions."
  echo "Dry run: nothing was deleted."
  exit 0
fi

tmutil_bin="${PRIVACY_SWEEP_TMUTIL:-tmutil}"

snapshot_dates() {
  local bin="$1" line
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "tmutil was not found. No snapshot dates to delete." >&2
    return 0
  fi
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    case "$line" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9])
        printf '%s\n' "$line"
        ;;
    esac
  done < <("$bin" listlocalsnapshotdates / 2>/dev/null || true)
}

revision_targets() {
  if [[ -n "${PRIVACY_SWEEP_RECOVERY_ROOT:-}" ]]; then
    local home="${PRIVACY_SWEEP_HOME:-$PRIVACY_SWEEP_RECOVERY_ROOT/Users/tester}"
    printf '%s\n' "$home/.DocumentRevisions-V100"
    printf '%s\n' "$PRIVACY_SWEEP_RECOVERY_ROOT/.DocumentRevisions-V100"
  else
    printf '%s\n' "$HOME/.DocumentRevisions-V100"
    printf '%s\n' "/.DocumentRevisions-V100"
  fi
}

if [[ "$PURGE_SNAP" == true ]]; then
  echo "-- Plan: APFS local snapshots --"
  if ! command -v "$tmutil_bin" >/dev/null 2>&1; then
    echo "tmutil was not found. Nothing would be deleted."
  else
    while IFS= read -r date || [[ -n "${date:-}" ]]; do
      [[ -n "$date" ]] || continue
      echo "Would run: $tmutil_bin deletelocalsnapshots $date"
    done < <(snapshot_dates "$tmutil_bin")
  fi
  echo
fi

if [[ "$PURGE_REV" == true ]]; then
  echo "-- Plan: Document Revisions --"
  echo "Only directories named .DocumentRevisions-V100 are eligible. The script does not sudo."
  while IFS= read -r target || [[ -n "${target:-}" ]]; do
    [[ -n "$target" ]] || continue
    case "$target" in
      */.DocumentRevisions-V100) ;;
      *) echo "Skipping unexpected path: $target"; continue ;;
    esac
    if [[ -d "$target" ]]; then
      echo "Would remove contents of: $target"
    else
      echo "Not present: $target"
    fi
  done < <(revision_targets)
  echo
fi

if [[ "$APPLY" != true || "$DRY_RUN" == true ]]; then
  echo "Dry run: nothing was deleted."
  exit 0
fi

if [[ "$PURGE_SNAP" == true ]]; then
  if confirm_phrase "DELETE LOCAL SNAPSHOTS"; then
    if ! command -v "$tmutil_bin" >/dev/null 2>&1; then
      echo "tmutil was not found. Snapshots were not deleted."
    else
      while IFS= read -r date || [[ -n "${date:-}" ]]; do
        [[ -n "$date" ]] || continue
        echo "Running: $tmutil_bin deletelocalsnapshots $date"
        "$tmutil_bin" deletelocalsnapshots "$date" || echo "tmutil failed for $date. That snapshot was left in place."
      done < <(snapshot_dates "$tmutil_bin")
    fi
  fi
fi

if [[ "$PURGE_REV" == true ]]; then
  if confirm_phrase "DELETE DOCUMENT REVISIONS"; then
    while IFS= read -r target || [[ -n "${target:-}" ]]; do
      [[ -n "$target" ]] || continue
      case "$target" in
        */.DocumentRevisions-V100) ;;
        *) echo "Refusing unexpected path: $target"; continue ;;
      esac
      if [[ ! -d "$target" ]]; then
        echo "Not present: $target"
        continue
      fi
      if [[ ! -w "$target" ]]; then
        echo "Not writable (no sudo attempted): $target"
        continue
      fi
      find -P "$target" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
      echo "Removed contents of: $target"
    done < <(revision_targets)
  fi
fi

echo "Done. Free space was not filled. Other stores were not touched."
