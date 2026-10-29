#!/usr/bin/env bash
# scan-remnants.sh - report-only names left behind by free-space wipe tools.
# Prints matching paths. Does not delete anything and does not print contents.
#
#   ./scan-remnants.sh
#   ./scan-remnants.sh --root /mnt/data --max-depth 2
#
# Names:
#   EFSTMPWP*                      cipher /w temporary directory
#   !FSTMPWP*                      same directory, renamed, left after an interrupt
#   SDELTEMP*                      SDelete temporary file
#   privacy-sweep-free-space-fill* this repo's Linux fill directory
#   eight or more leading z's      cleaner-rewritten filenames
#
# A live scan (no --root) looks at each mount at depth 2, and at temp and
# home at depth 3. It is not a full-disk forensic walk.
set -euo pipefail

MAX_DEPTH=2
ROOTS=()
EXPLICIT=false
LIVE_EXTRA=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "Missing path after --root" >&2; exit 1; }
      ROOTS+=("$2")
      EXPLICIT=true
      shift 2
      ;;
    --max-depth)
      [[ $# -ge 2 ]] || { echo "Missing number after --max-depth" >&2; exit 1; }
      MAX_DEPTH="$2"
      shift 2
      ;;
    --no-extra)
      LIVE_EXTRA=false
      shift
      ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$EXPLICIT" == false && -n "${PRIVACY_SWEEP_RECOVERY_ROOT:-}" ]]; then
  ROOTS+=("$PRIVACY_SWEEP_RECOVERY_ROOT")
  EXPLICIT=true
fi

is_skipped_mount() {
  case "$1" in
    /proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|/snap|/snap/*)
      return 0
      ;;
  esac
  return 1
}

if [[ "$EXPLICIT" == false ]]; then
  if command -v findmnt >/dev/null 2>&1; then
    while IFS= read -r target || [[ -n "${target:-}" ]]; do
      [[ -n "${target:-}" ]] || continue
      is_skipped_mount "$target" && continue
      ROOTS+=("$target")
    done < <(findmnt -n -o TARGET -l 2>/dev/null || true)
  fi
  if [[ ${#ROOTS[@]} -eq 0 ]]; then
    ROOTS+=("/")
  fi
fi

declare -A SEEN=()
FOUND=()

add_matches() {
  local root="$1" depth="$2" line
  [[ -d "$root" ]] || return 0
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -n "${line:-}" ]] || continue
    if [[ -z "${SEEN[$line]:-}" ]]; then
      SEEN["$line"]=1
      FOUND+=("$line")
    fi
  done < <(find -P "$root" -xdev -maxdepth "$depth" \
    \( -name 'EFSTMPWP*' -o -name '!FSTMPWP*' -o -name 'SDELTEMP*' \
       -o -name 'privacy-sweep-free-space-fill*' -o -iname 'zzzzzzzz*' \) \
    -print 2>/dev/null || true)
}

for root in "${ROOTS[@]}"; do
  add_matches "$root" "$MAX_DEPTH"
done

if [[ "$EXPLICIT" == false && "$LIVE_EXTRA" == true ]]; then
  for extra in /tmp /var/tmp "${TMPDIR:-}" "${HOME:-}"; do
    [[ -n "$extra" && -d "$extra" ]] || continue
    add_matches "$extra" 3
  done
fi

echo "-- Wipe-tool remnants --"
echo "Patterns: EFSTMPWP, !FSTMPWP, SDELTEMP, privacy-sweep-free-space-fill, names of eight or more z's."
if [[ "$EXPLICIT" == true ]]; then
  echo "Scope: depth ${MAX_DEPTH} from each given root. Not a full-disk search. Contents are not read."
else
  echo "Scope: mount roots at depth ${MAX_DEPTH}, temp and home at depth 3. Not a full-disk search. Contents are not read."
fi
echo "Count: ${#FOUND[@]}"
if [[ ${#FOUND[@]} -gt 0 ]]; then
  printf '%s\n' "${FOUND[@]}" | sort -u | sed 's/^/  /'
fi
echo
