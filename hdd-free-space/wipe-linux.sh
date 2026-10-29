#!/usr/bin/env bash
# wipe-linux.sh - opt-in free-space fill for a hard disk (Linux).
# Not part of clear-all or privacy-sweep.sh. Never runs unless you ask.
#
#   ./wipe-linux.sh --dry-run
#   ./wipe-linux.sh --dry-run --volume /mnt/data
#   ./wipe-linux.sh                         # show the plan, then ask
#   ./wipe-linux.sh --yes --volume /mnt/data
#   ./wipe-linux.sh --i-know-this-is-ssd    # override an SSD or unknown refusal
#
# Refuses SSDs and unknown media unless --i-know-this-is-ssd is present.
# That override prints a warning: filling free space does not reliably erase
# NAND (TRIM, wear leveling, overprovisioning).
#
# Does not remove Volume Shadow Copies, APFS snapshots, or Document Revisions.
# On the root filesystem the fill stops about 128 MiB short so the machine
# can still delete the fill file.
#
# --simulate and PRIVACY_SWEEP_WIPE_SIMULATE=1 are test hooks. They do not
# overwrite free space. The script says so in the output.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=hdd-free-space/media-type.sh
source "$DIR/media-type.sh"

DRY_RUN=false
ASSUME_YES=false
ALLOW_SSD=false
SIMULATE=false
VOLUME="${HOME:-/}"

if [[ "${PRIVACY_SWEEP_WIPE_SIMULATE:-}" == "1" ]]; then
  SIMULATE=true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --yes|-y) ASSUME_YES=true ;;
    --volume)
      [[ $# -ge 2 ]] || { echo "Missing path after --volume" >&2; exit 1; }
      VOLUME="$2"
      shift
      ;;
    --i-know-this-is-ssd) ALLOW_SSD=true ;;
    --simulate) SIMULATE=true ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ ! -e "$VOLUME" ]]; then
  echo "Path does not exist: $VOLUME" >&2
  exit 1
fi
if command -v readlink >/dev/null 2>&1; then
  VOLUME="$(readlink -f -- "$VOLUME")"
fi

if [[ -n "${PRIVACY_SWEEP_MOUNT_POINT:-}" ]]; then
  mount="$PRIVACY_SWEEP_MOUNT_POINT"
elif command -v findmnt >/dev/null 2>&1; then
  mount="$(findmnt -n -o TARGET --target "$VOLUME" 2>/dev/null || true)"
else
  mount=""
fi
if [[ -z "$mount" ]]; then
  mount="$(df -P "$VOLUME" | awk 'NR==2 { print $NF }')"
fi

free_bytes() {
  if [[ -n "${PRIVACY_SWEEP_FREE_BYTES:-}" ]]; then
    printf '%s\n' "$PRIVACY_SWEEP_FREE_BYTES"
    return 0
  fi
  df -B1 -P "$1" | awk 'NR==2 { print $4 }'
}

avail="$(free_bytes "$mount")"
if [[ ! "$avail" =~ ^[0-9]+$ ]]; then
  echo "Could not read free space for $mount." >&2
  exit 1
fi

MEDIA_KIND="unknown"
MEDIA_REASON="unresolved"
if [[ -n "${PRIVACY_SWEEP_MEDIA_TYPE:-}" ]]; then
  case "$PRIVACY_SWEEP_MEDIA_TYPE" in
    hdd|ssd|unknown) ;;
    *) echo "PRIVACY_SWEEP_MEDIA_TYPE must be hdd, ssd, or unknown." >&2; exit 1 ;;
  esac
  MEDIA_KIND="$PRIVACY_SWEEP_MEDIA_TYPE"
  MEDIA_REASON="override"
else
  disk="$(resolve_disk_for_path "$VOLUME")"
  if [[ -z "$disk" ]]; then
    MEDIA_KIND="unknown"
    MEDIA_REASON="could not resolve a block device"
  else
    set_media_kind_for_disk "$disk"
  fi
fi

rate=$((80 * 1024 * 1024))
seconds=$((avail / rate))
if [[ "$seconds" -lt 60 ]]; then
  rough="under 1 minute"
else
  rough="about $((seconds / 60)) minutes"
fi

if [[ -d "$VOLUME" && -w "$VOLUME" ]]; then
  fill_parent="$VOLUME"
else
  fill_parent="$mount"
fi
fill_dir="${fill_parent}/privacy-sweep-free-space-fill"
owned=0

cleanup() {
  if [[ "${owned}" -eq 1 && -n "${fill_dir}" ]]; then
    case "${fill_dir}" in
      */privacy-sweep-free-space-fill)
        rm -rf -- "${fill_dir}"
        ;;
      *)
        echo "Refusing to remove unexpected path: ${fill_dir}" >&2
        ;;
    esac
  fi
}
trap cleanup EXIT

print_fingerprint_warning() {
  cat <<'EOF'
WARNING: free-space wiping leaves fingerprints examiners are trained to
spot. Windows cipher /w can leave a directory named EFSTMPWP, or
!FSTMPWP if it is interrupted. SDelete can leave a zero-byte file named
SDELTEMP. Some cleaners rename deleted files to a long run of z
characters. This Linux tool uses a directory named
privacy-sweep-free-space-fill and removes it when it finishes. If it is
interrupted, that name can remain. Wiping free space is common among
ordinary users. The name alone is not proof of wrongdoing.
EOF
}

print_snapshot_note() {
  cat <<'EOF'
This does not remove Volume Shadow Copies, APFS snapshots, local Time
Machine snapshots, or Document Revisions. Those can still hold older
copies of files after free space is filled.
EOF
}

echo "== HDD free-space fill (Linux) =="
echo "Requested path: $VOLUME"
if [[ -n "${PRIVACY_SWEEP_MOUNT_POINT:-}" ]]; then
  echo "Volume: $mount (PRIVACY_SWEEP_MOUNT_POINT override)"
else
  echo "Volume: $mount"
fi
echo "Free bytes: $avail"
echo "Estimated impact: up to $avail bytes written in a fill file, then deleted. Other files are not removed."
echo "Rough time guess: $rough at 80 MiB/s (not a measurement)."
echo "Media: $MEDIA_KIND ($MEDIA_REASON)"
echo "Tool: fill-until-full + sync + unlink"
print_snapshot_note
print_fingerprint_warning

refuse() {
  cat <<EOF
Refusing to fill free space: media is ${MEDIA_KIND} (${MEDIA_REASON}).
Free-space fill on an SSD is theater. TRIM, wear leveling, and
overprovisioned areas are handled by the drive, and a file written from
userspace cannot reliably reach the old NAND pages.
Nothing was written.
For day-to-day protection, keep full-disk encryption on. For disposal,
destroy the encryption key or use the drive vendor's erase tool.
See ${ROOT}/docs/leave-no-trace.md
To override this refusal: --i-know-this-is-ssd
EOF
  exit 2
}

if [[ "$MEDIA_KIND" != "hdd" && "$ALLOW_SSD" != true ]]; then
  refuse
fi

if [[ "$ALLOW_SSD" == true && "$MEDIA_KIND" != "hdd" ]]; then
  cat <<'EOF'
WARNING: --i-know-this-is-ssd was set.
Free-space fill on an SSD is theater. It will not reliably erase NAND,
and it still leaves a wipe-tool fingerprint. Continuing only because you
asked.
EOF
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run: nothing was written."
  exit 0
fi

if [[ "$ASSUME_YES" != true ]]; then
  answer=""
  read -r -p "Fill free space on ${mount} and then delete the fill file? [y/N] " answer || answer=""
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Cancelled. Nothing was written."
    exit 0
  fi
fi

if [[ "$SIMULATE" == true ]]; then
  echo "SIMULATION: no free-space overwrite was performed."
  echo "SIMULATION: the fill was not run. This does not erase a disk."
  mkdir -p "$fill_dir"
  owned=1
  printf 'x\n' > "$fill_dir/fill"
  sync || true
  rm -rf -- "$fill_dir"
  owned=0
  echo "Fill file removed."
else
  # Test hook: a mount override must not be able to fill the real disk by accident.
  if [[ -n "${PRIVACY_SWEEP_MOUNT_POINT:-}" && "${PRIVACY_SWEEP_ALLOW_REAL_FILL:-}" != "1" ]]; then
    echo "Refusing a real fill while PRIVACY_SWEEP_MOUNT_POINT is set." >&2
    echo "This override is for dry runs and --simulate. Nothing was written." >&2
    exit 1
  fi
  if [[ -e "$fill_dir" ]]; then
    echo "Refusing to continue: $fill_dir already exists." >&2
    echo "If that is a leftover from an interrupted run, remove it yourself, then run again." >&2
    exit 1
  fi
  mkdir -p "$fill_dir"
  owned=1
  pattern="$fill_dir/pattern"
  fill="$fill_dir/fill"
  dd if=/dev/urandom of="$pattern" bs=1048576 count=1 status=none
  : > "$fill"
  margin=0
  if [[ "$mount" == "/" ]]; then
    margin=$((128 * 1024 * 1024))
    echo "Root filesystem: stopping about 128 MiB short so the fill file can be removed."
  fi
  while true; do
    avail="$(free_bytes "$mount")"
    if [[ "$margin" -gt 0 && "$avail" -le "$margin" ]]; then
      echo "Stopped with ${avail} bytes free (root safety margin)."
      break
    fi
    if [[ "$margin" -eq 0 && "$avail" -lt 1048576 ]]; then
      dd if="$pattern" of="$fill" bs=1 count="$avail" oflag=append conv=notrunc status=none || true
      echo "Less than 1 MiB was left; stopped."
      break
    fi
    before="$avail"
    if ! cat "$pattern" >> "$fill"; then
      echo "The volume stopped accepting writes."
      break
    fi
    sync || true
    after="$(free_bytes "$mount")"
    if [[ "$after" -ge "$before" ]]; then
      echo "Stopped: free space did not shrink. The filesystem may be compressing or sparsing the fill file."
      break
    fi
  done
  sync || true
  rm -rf -- "$fill_dir"
  owned=0
  sync || true
  echo "Fill file removed."
fi

echo "-- After the fill: remnant scan --"
bash "$ROOT/audit/scan-remnants.sh" --root "$fill_parent" --max-depth 2
if [[ "$fill_parent" != "$mount" ]]; then
  bash "$ROOT/audit/scan-remnants.sh" --root "$mount" --max-depth 2
fi
echo "Done. Other files on the volume were not removed."
