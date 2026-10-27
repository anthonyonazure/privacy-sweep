#!/usr/bin/env bash
# memory.sh - sleepimage (macOS) and swap (Linux). Audit, plus opt-in actions.
# Dry-run unless --apply. --yes does not delete.
# Not part of clear-all. Windows pagefile/hiberfil: memory-windows.ps1.
#
#   ./memory.sh
#   ./memory.sh --dry-run --remove-sleepimage
#   ./memory.sh --remove-sleepimage --apply          # only if hibernatemode is 0
#   ./memory.sh --dry-run --purge-swap
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=lib/confirm.sh
source "$ROOT/lib/confirm.sh"
# shellcheck source=audit/report-lib.sh
source "$ROOT/audit/report-lib.sh"

DRY_RUN=false
APPLY=false
DO_SLEEP=false
DO_SWAP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --apply) APPLY=true ;;
    --yes|-y) ;;
    --remove-sleepimage) DO_SLEEP=true ;;
    --purge-swap) DO_SWAP=true ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

OS_NAME="${PRIVACY_SWEEP_OS:-$(uname -s)}"
vm="${PRIVACY_SWEEP_VM_ROOT:-/private/var/vm}"
if [[ -n "${PRIVACY_SWEEP_RECOVERY_ROOT:-}" ]]; then
  vm="$PRIVACY_SWEEP_RECOVERY_ROOT/private/var/vm"
fi

echo "== Memory residue (presence and size; bytes are not read) =="
echo "WARNING: disabling hibernation or purging swap destroys a copy of memory that backups and crash analysis use."
echo "Nothing is deleted unless you pass --apply and type the confirmation phrase. --yes does not delete."
echo "This is not part of clear-all."
echo

echo "-- macOS sleepimage and swap files --"
if [[ "$OS_NAME" == "Darwin" || -n "${PRIVACY_SWEEP_RECOVERY_ROOT:-}" ]]; then
  echo "macOS has encrypted sleepimage since 10.7. This report still only shows presence and size."
  report_file_presence "sleepimage" "$vm/sleepimage"
  if [[ -d "$vm" ]]; then
    shopt -s nullglob
    swaps=("$vm"/swapfile*)
    shopt -u nullglob
    if [[ ${#swaps[@]} -eq 0 ]]; then
      echo "No swapfile* under $vm"
      echo
    else
      for swap in "${swaps[@]}"; do
        report_file_presence "vm swap" "$swap"
      done
    fi
  fi
  mode="${PRIVACY_SWEEP_HIBERNATEMODE:-}"
  if [[ -z "$mode" ]] && command -v pmset >/dev/null 2>&1; then
    mode="$(pmset -g 2>/dev/null | awk '/hibernatemode/ { print $2; exit }' || true)"
  fi
  if [[ -z "$mode" ]]; then
    echo "hibernatemode: unreadable. Sleepimage removal is refused until the mode is known."
  else
    echo "hibernatemode: $mode"
    echo "Removal is allowed by this script only when hibernatemode is 0 (sleep, not hibernate)."
  fi
  echo "This script does not change hibernatemode."
  echo
else
  echo "Not a macOS report on this host."
  echo
fi

echo "-- Linux swap --"
swap_src="${PRIVACY_SWEEP_SWAP_FILE:-/proc/swaps}"
if [[ -f "$swap_src" ]]; then
  echo "Path: $swap_src"
  awk 'NR>1 { print "  "$1"  size_kb="$3 }' "$swap_src" 2>/dev/null || true
  echo "Swap file contents are not read."
else
  echo "Path: $swap_src"
  echo "Present: no"
fi
echo "Advisory: swapoff, then mkswap, then swapon, rewrites swap. It needs root."
echo "A journal or installer can recreate swap. This does not encrypt the disk."
echo

if [[ "$DO_SLEEP" == true ]]; then
  target="$vm/sleepimage"
  echo "-- Plan: remove sleepimage --"
  echo "Would remove: $target"
  echo "Only when hibernatemode is 0, the path is a regular file, and it is not a symlink."
  if [[ "$APPLY" == true && "$DRY_RUN" != true ]]; then
    if [[ "${mode:-}" != "0" ]]; then
      echo "Refusing: hibernatemode is '${mode:-unreadable}', not 0. Nothing was deleted."
    elif confirm_phrase "REMOVE SLEEPIMAGE"; then
      if [[ -L "$target" ]]; then
        echo "Refusing: $target is a symlink. Nothing was deleted."
      elif [[ ! -f "$target" ]]; then
        echo "Not present: $target"
      else
        rm -f -- "$target"
        echo "Removed: $target"
      fi
    fi
  else
    echo "Dry run: nothing was deleted."
  fi
  echo
fi

if [[ "$DO_SWAP" == true ]]; then
  echo "-- Plan: purge swap --"
  echo "Would run, as root, for each swap device listed above:"
  echo "  swapoff <device>"
  echo "  mkswap <device>"
  echo "  swapon <device>"
  if [[ "$APPLY" == true && "$DRY_RUN" != true ]]; then
    if confirm_phrase "PURGE SWAP"; then
      if [[ "${PRIVACY_SWEEP_SWAP_SIMULATE:-}" == "1" ]]; then
        log="${PRIVACY_SWEEP_SWAP_LOG:-}"
        if [[ -n "$log" ]]; then
          printf '%s\n' 'swapoff' 'mkswap' 'swapon' >> "$log"
        fi
        echo "SIMULATION: swap was not changed."
      elif [[ "$(id -u)" -ne 0 ]]; then
        echo "Refusing: swap purge needs root. Nothing was changed."
      elif [[ ! -f "$swap_src" ]]; then
        echo "No swap table at $swap_src. Nothing was changed."
      else
        while IFS= read -r dev || [[ -n "${dev:-}" ]]; do
          [[ -n "$dev" ]] || continue
          case "$dev" in
            /dev/*|/*) ;;
            *) echo "Skipping unexpected swap path: $dev"; continue ;;
          esac
          echo "Running: swapoff $dev"
          swapoff "$dev" || { echo "swapoff failed for $dev. Left as it was."; continue; }
          echo "Running: mkswap $dev"
          mkswap "$dev" || { echo "mkswap failed for $dev. Swap may be off."; continue; }
          echo "Running: swapon $dev"
          swapon "$dev" || echo "swapon failed for $dev."
        done < <(awk 'NR>1 { print $1 }' "$swap_src")
      fi
    fi
  else
    echo "Dry run: nothing was changed."
  fi
  echo
fi

if [[ "$DO_SLEEP" != true && "$DO_SWAP" != true ]]; then
  echo "No opt-in flag was set. Pass --remove-sleepimage and/or --purge-swap."
  echo "Dry run: nothing was deleted."
fi

echo "Audit only: counts, sizes, and paths. Contents, passwords, message bodies, and row values are not printed."
echo "Nothing else was deleted."
