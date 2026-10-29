#!/usr/bin/env bash
# media-type.sh - HDD vs SSD check used by wipe-linux.sh.
# Sourced. Trusts the kernel rotational flag (1 = spinning disk, 0 = SSD).
# Some virtual disks report rotational=1 even when the file behind them is
# not a hard disk. When the flag is missing, the caller treats it as unknown
# and refuses to fill free space.

sys_block_root() {
  printf '%s\n' "${PRIVACY_SWEEP_SYS_BLOCK:-/sys/block}"
}

# Map a partition name to the whole disk: sda1 -> sda, nvme0n1p2 -> nvme0n1.
disk_from_name() {
  local dev="${1##*/}"
  dev="${dev%%,*}"
  dev="${dev%%\[*}"
  if [[ "$dev" =~ ^(nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$dev" =~ ^(mmcblk[0-9]+)p[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$dev" =~ ^([A-Za-z]+)[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf '%s\n' "$dev"
}

# Sets MEDIA_KIND (hdd|ssd|unknown) and MEDIA_REASON. No stdout.
# Those two names are read by wipe-linux.sh after this function returns.
# shellcheck disable=SC2034
set_media_kind_for_disk() {
  local disk="$1" rota="" path
  path="$(sys_block_root)/${disk}/queue/rotational"
  if [[ ! -r "$path" ]]; then
    MEDIA_KIND="unknown"
    MEDIA_REASON="no rotational flag for ${disk}"
    return 0
  fi
  rota="$(tr -d '[:space:]' < "$path")"
  case "$rota" in
    1)
      MEDIA_KIND="hdd"
      MEDIA_REASON="rotational=1 (${disk})"
      ;;
    0)
      MEDIA_KIND="ssd"
      MEDIA_REASON="rotational=0 (${disk})"
      ;;
    *)
      MEDIA_KIND="unknown"
      MEDIA_REASON="rotational flag '${rota}' for ${disk}"
      ;;
  esac
}

# Prints the whole-disk name for a filesystem path, or an empty line.
resolve_disk_for_path() {
  local path="$1" source="" pk=""
  if [[ -n "${PRIVACY_SWEEP_BLOCK_DEVICE:-}" ]]; then
    disk_from_name "$PRIVACY_SWEEP_BLOCK_DEVICE"
    return 0
  fi
  if [[ -n "${PRIVACY_SWEEP_FIND_SOURCE:-}" ]]; then
    source="$PRIVACY_SWEEP_FIND_SOURCE"
  elif command -v findmnt >/dev/null 2>&1; then
    source="$(findmnt -n -o SOURCE --target "$path" 2>/dev/null || true)"
  fi
  source="${source%%\[*}"
  source="${source##*/}"
  if [[ -z "$source" ]]; then
    printf '\n'
    return 0
  fi
  if [[ -z "${PRIVACY_SWEEP_FIND_SOURCE:-}" ]] && command -v lsblk >/dev/null 2>&1; then
    pk="$(lsblk -n -l -o PKNAME "/dev/$source" 2>/dev/null | awk 'NR==1 { print; exit }' || true)"
    if [[ -n "$pk" ]]; then
      disk_from_name "$pk"
      return 0
    fi
  fi
  disk_from_name "$source"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  if [[ $# -eq 0 ]]; then
    echo "Source this file from wipe-linux.sh. Or: media-type.sh DEVICE-NAME" >&2
    exit 1
  fi
  disk_from_name "$1"
fi
