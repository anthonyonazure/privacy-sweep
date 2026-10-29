#!/usr/bin/env bash
# audit-recovery-macos.sh - part of privacy-sweep (report only)
# Local APFS / Time Machine snapshots, Document Revisions size, external
# .Trashes counts, sleepimage/swap presence, FileVault on/off, and a shallow
# remnant-name scan. Nothing is deleted. Snapshot names are timestamps.
# Document names, Trash names, sleepimage bytes, and recovery keys are not
# printed.
#
#   ./audit-recovery-macos.sh
#   PRIVACY_SWEEP_RECOVERY_ROOT=/path/to/fixture ./audit-recovery-macos.sh
set -euo pipefail

for arg in "$@"; do
  case "$arg" in
    --dry-run|--yes|-y) ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=audit/report-lib.sh
source "$SCRIPT_DIR/report-lib.sh"

FIXTURE="${PRIVACY_SWEEP_RECOVERY_ROOT:-}"
OS_NAME="${PRIVACY_SWEEP_OS:-$(uname -s)}"
if [[ -z "$FIXTURE" && "$OS_NAME" != "Darwin" ]]; then
  echo "This report is for macOS. Detected: $OS_NAME." >&2
  exit 1
fi
if [[ -n "${PRIVACY_SWEEP_MACOS_RECOVERY_DONE:-}" && -z "${PRIVACY_SWEEP_FORCE_RECOVERY:-}" ]]; then
  echo "macOS recovery structures were already reported in this run. Skipping the duplicate."
  exit 0
fi

echo "== macOS recovery structures (report only; nothing deleted) =="
echo

run_tmutil() {
  local sub="$1"
  local bin="${PRIVACY_SWEEP_TMUTIL:-tmutil}"
  if [[ -n "$FIXTURE" && -f "$FIXTURE/tmutil-${sub}.txt" ]]; then
    cat "$FIXTURE/tmutil-${sub}.txt"
    return 0
  fi
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "tmutil was not found."
    return 0
  fi
  # listlocalsnapshots / listlocalsnapshotdates only. Never a delete subcommand.
  "$bin" "$sub" / 2>&1 || true
}

echo "-- Local APFS / Time Machine snapshots --"
echo "Command: tmutil listlocalsnapshots /"
snaps="$(run_tmutil listlocalsnapshots)"
printf '%s\n' "$snaps" | sed 's/^/  /'
snap_count="$(printf '%s\n' "$snaps" | grep -c 'com.apple.TimeMachine' || true)"
echo "Local snapshot count: ${snap_count:-0}"
echo "Command: tmutil listlocalsnapshotdates /"
dates="$(run_tmutil listlocalsnapshotdates)"
printf '%s\n' "$dates" | sed 's/^/  /'
echo "Snapshots are listed, not deleted."
echo

if [[ -n "$FIXTURE" ]]; then
  home="${PRIVACY_SWEEP_HOME:-$FIXTURE/Users/tester}"
  rev_paths=("$home/.DocumentRevisions-V100" "$FIXTURE/.DocumentRevisions-V100")
  volroot="$FIXTURE/Volumes"
  vm="$FIXTURE/private/var/vm"
else
  home="$HOME"
  rev_paths=("$home/.DocumentRevisions-V100" "/.DocumentRevisions-V100")
  volroot="/Volumes"
  vm="/private/var/vm"
fi

for rev in "${rev_paths[@]}"; do
  report_dir_summary "Document Revisions" "$rev"
done

echo "-- External volume Trash --"
if [[ -d "$volroot" ]]; then
  shopt -s nullglob
  trash_dirs=("$volroot"/*/.Trashes)
  shopt -u nullglob
  if [[ ${#trash_dirs[@]} -eq 0 ]]; then
    echo "No .Trashes directories under $volroot"
  else
    for trash in "${trash_dirs[@]}"; do
      report_dir_summary "External .Trashes" "$trash"
    done
  fi
else
  echo "Path: $volroot"
  echo "Present: no"
fi
echo

echo "-- sleepimage and swap --"
echo "Presence and size only. The bytes are not read."
echo "macOS has encrypted sleepimage since 10.7. This report still only shows presence and size."
if [[ -d "$vm" ]]; then
  report_file_presence "sleepimage" "$vm/sleepimage"
  shopt -s nullglob
  swap_files=("$vm"/swapfile*)
  shopt -u nullglob
  if [[ ${#swap_files[@]} -eq 0 ]]; then
    echo "No swapfile* under $vm"
    echo
  else
    for swap in "${swap_files[@]}"; do
      report_file_presence "vm swap" "$swap"
    done
  fi
else
  echo "Path: $vm"
  echo "Present: no"
  echo
fi

filter_filevault() {
  local line
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -n "${line:-}" ]] || continue
    if [[ "$line" =~ [Ff]ile[Vv]ault[[:space:]]+is[[:space:]]+(On|Off) ]]; then
      printf '%s\n' "$line"
    fi
  done
  return 0
}

echo "-- FileVault (on/off only) --"
fv_bin="${PRIVACY_SWEEP_FDESETUP:-fdesetup}"
if [[ -n "$FIXTURE" && -f "$FIXTURE/fdesetup-status.txt" ]]; then
  raw="$(cat "$FIXTURE/fdesetup-status.txt")"
elif command -v "$fv_bin" >/dev/null 2>&1; then
  raw="$("$fv_bin" status 2>&1 || true)"
else
  raw=""
  echo "fdesetup was not found."
fi
if [[ -n "$raw" ]]; then
  filtered="$(printf '%s\n' "$raw" | filter_filevault)"
  if [[ -n "$filtered" ]]; then
    printf '%s\n' "$filtered"
  else
    echo "FileVault status: unavailable (unrecognized output omitted)."
  fi
fi
echo "Recovery keys are not requested and are not printed."
echo

echo "cipher and SDelete are Windows tools. This is a shallow name scan in case a volume was filled elsewhere."
if [[ -n "$FIXTURE" ]]; then
  bash "$SCRIPT_DIR/scan-remnants.sh" --root "$FIXTURE" --max-depth 2
else
  extra=()
  [[ -d /Volumes ]] && extra+=(--root /Volumes)
  [[ -n "${HOME:-}" && -d "$HOME" ]] && extra+=(--root "$HOME")
  if [[ ${#extra[@]} -eq 0 ]]; then
    echo "Count: 0 (no home or /Volumes to scan)"
    echo
  else
    bash "$SCRIPT_DIR/scan-remnants.sh" --max-depth 2 "${extra[@]}"
  fi
fi
echo "Nothing above was deleted."
