#!/usr/bin/env bash
# audit-recovery-linux.sh - part of privacy-sweep (report only)
# Swap presence, LUKS/cryptsetup status, and free-space-tool remnant names.
# It does not delete anything. It does not print key files, passphrases, or
# the contents of a swap file.
#
#   ./audit-recovery-linux.sh
#   PRIVACY_SWEEP_RECOVERY_ROOT=/path/to/fixture ./audit-recovery-linux.sh
#
# Login records stay out of this report. See SECURITY.md.
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
if [[ -z "$FIXTURE" && "$(uname -s)" != "Linux" ]]; then
  echo "This report is for Linux. Detected: $(uname -s)." >&2
  exit 1
fi

echo "== Linux recovery structures (report only; nothing deleted) =="
echo

echo "-- Swap --"
if [[ -n "$FIXTURE" ]]; then
  swaps_file="$FIXTURE/proc/swaps"
else
  swaps_file="/proc/swaps"
fi
echo "Path: $swaps_file"
if [[ -f "$swaps_file" ]]; then
  awk 'NR>1 && NF>=3 { printf "Entry: %s type=%s size_kb=%s\n", $1, $2, $3 }' "$swaps_file"
  count="$(awk 'NR>1 && NF>=3 { c++ } END { print c+0 }' "$swaps_file")"
  echo "Swap entries: $count"
else
  echo "Swap entries: 0 (not present)"
fi
if [[ -n "$FIXTURE" ]]; then
  for candidate in "$FIXTURE/swapfile" "$FIXTURE/swap.img"; do
    if [[ -e "$candidate" ]]; then
      report_file_presence "Swap file" "$candidate"
    fi
  done
else
  for candidate in /swapfile /swap.img; do
    if [[ -e "$candidate" ]]; then
      report_file_presence "Swap file" "$candidate"
    fi
  done
fi
echo "Swap file contents are not read."
echo

filter_cryptsetup_status() {
  local line
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -n "${line:-}" ]] || continue
    if [[ "$line" == *" is active"* || "$line" == *" is inactive"* ]]; then
      printf '%s\n' "$line"
      continue
    fi
    # Allow type, cipher, device, size, and mode. Drop keysize, key
    # location, passphrases, and anything else.
    if [[ "$line" =~ ^[[:space:]]*(type|cipher|device|size|mode): ]]; then
      printf '%s\n' "$line"
    fi
  done
  return 0
}

echo "-- LUKS / cryptsetup (no keys) --"
if [[ -n "$FIXTURE" ]]; then
  crypttab="$FIXTURE/etc/crypttab"
  lsblk_file="$FIXTURE/lsblk-crypt.txt"
  status_file="$FIXTURE/cryptsetup-status.txt"
else
  crypttab="/etc/crypttab"
  lsblk_file=""
  status_file=""
fi

if [[ -f "$crypttab" ]]; then
  # First field only. The third field is often a key file; it is not printed.
  awk 'NF && $1 !~ /^#/ { print "crypttab name: " $1 }' "$crypttab"
else
  echo "crypttab: not present"
fi

crypt_names=()
if [[ -n "$lsblk_file" && -f "$lsblk_file" ]]; then
  while IFS= read -r name || [[ -n "${name:-}" ]]; do
    [[ -n "${name:-}" ]] || continue
    crypt_names+=("$name")
    echo "Active crypt device: $name"
  done < <(awk '$2 == "crypt" { print $1 }' "$lsblk_file")
elif [[ -z "$FIXTURE" ]] && command -v lsblk >/dev/null 2>&1; then
  while IFS= read -r name || [[ -n "${name:-}" ]]; do
    [[ -n "${name:-}" ]] || continue
    crypt_names+=("$name")
    echo "Active crypt device: $name"
  done < <(lsblk -n -l -o NAME,TYPE 2>/dev/null | awk '$2 == "crypt" { print $1 }' || true)
else
  if [[ -z "$FIXTURE" ]]; then
    echo "lsblk was not found. Active mapper names were not queried."
  fi
fi
if [[ ${#crypt_names[@]} -eq 0 ]]; then
  echo "Active crypt devices: 0"
fi

if [[ -n "$status_file" && -f "$status_file" ]]; then
  echo "cryptsetup status (filtered):"
  filter_cryptsetup_status < "$status_file"
elif [[ -z "$FIXTURE" ]] && command -v cryptsetup >/dev/null 2>&1; then
  for name in "${crypt_names[@]}"; do
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "Skipping unusual mapper name."
      continue
    fi
    echo "cryptsetup status $name (filtered):"
    filter_cryptsetup_status < <(cryptsetup status "$name" 2>&1 || true)
  done
elif [[ -z "$FIXTURE" ]]; then
  echo "cryptsetup was not found. Status was not queried."
fi
echo "Key files, passphrases, and keyslots are not printed."
echo

if [[ -n "$FIXTURE" ]]; then
  bash "$SCRIPT_DIR/scan-remnants.sh" --root "$FIXTURE" --max-depth 2
else
  bash "$SCRIPT_DIR/scan-remnants.sh"
fi
echo "This report does not delete swap, LUKS headers, or remnant names."
