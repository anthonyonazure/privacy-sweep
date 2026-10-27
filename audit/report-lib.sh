#!/usr/bin/env bash
# report-lib.sh - helpers for the report-only audits.
# Sourced by the recovery reports. Prints sizes and counts, never contents.
# Direct execution:  ./report-lib.sh /path/to/file

file_bytes() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return 1
  fi
  # GNU stat uses -c. BSD/macOS stat uses -f. Try GNU first.
  if stat -c %s "$path" >/dev/null 2>&1; then
    stat -c %s "$path"
  else
    stat -f %z "$path"
  fi
}

# Presence and size for one file. Does not open it.
report_file_presence() {
  local label="$1" path="$2" bytes=""
  echo "-- $label --"
  echo "Path: $path"
  if [[ ! -e "$path" ]]; then
    echo "Present: no"
    echo
    return 0
  fi
  bytes="$(file_bytes "$path" 2>/dev/null || true)"
  echo "Present: yes"
  echo "Bytes: ${bytes:-unreadable}"
  echo "Contents are not read."
  echo
}

# Directory presence, file count, and size in KiB. Does not list names.
report_dir_summary() {
  local label="$1" path="$2" files="" size=""
  echo "-- $label --"
  echo "Path: $path"
  if [[ ! -e "$path" ]]; then
    echo "Present: no"
    echo
    return 0
  fi
  if [[ ! -d "$path" ]]; then
    echo "Present: yes (not a directory)"
    echo
    return 0
  fi
  # find's non-zero status on an unreadable directory must not abort the caller.
  files="$(find -P "$path" -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
  size="$(du -sk "$path" 2>/dev/null | awk '{print $1}' || true)"
  echo "Present: yes"
  echo "Files: ${files:-0}"
  if [[ -n "$size" ]]; then
    echo "SizeKiB: $size"
  else
    echo "SizeKiB: unreadable"
  fi
  echo "Names inside this store are not listed."
  echo
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  if [[ $# -eq 0 ]]; then
    echo "Usage: report-lib.sh FILE..." >&2
    exit 1
  fi
  for path in "$@"; do
    if bytes="$(file_bytes "$path" 2>/dev/null)"; then
      echo "$path $bytes"
    else
      echo "$path missing"
    fi
  done
fi
