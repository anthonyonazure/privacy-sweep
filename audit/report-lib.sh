#!/usr/bin/env bash
# report-lib.sh - helpers for the report-only audits.
# Sourced by the recovery reports. Prints sizes and counts, never contents.
# Direct execution:  ./report-lib.sh /path/to/file
#
# Large scans go through run_bounded_capture. The limit is
# PRIVACY_SWEEP_SCAN_TIMEOUT seconds (default 20). 0 means no limit.
# A timed-out scan prints "scan timed out after Ns; partial or skipped"
# and returns success so the audit continues.

SCAN_TIMED_OUT=0
SCAN_RC=0

scan_timeout_seconds() {
  local n="${PRIVACY_SWEEP_SCAN_TIMEOUT:-20}"
  case "$n" in
    ''|*[!0-9]*) printf '%s\n' 20 ;;
    *) printf '%s\n' "$n" ;;
  esac
}

# Background wall clock for shell functions, which perl cannot exec.
# Writes command stdout to $2. Returns 142 on timeout.
_bounded_background() {
  local seconds="$1" tmp="$2" pid i rc
  shift 2
  rc=0
  "$@" >"$tmp" 2>/dev/null &
  pid=$!
  i=0
  while [[ "$i" -lt "$seconds" ]]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" || rc=$?
      return "$rc"
    fi
    sleep 1
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 142
  fi
  wait "$pid" || rc=$?
  return "$rc"
}

# Runs "$@" with the scan limit. Prints stdout, then a status marker.
# Always returns 0. The marker is parsed by run_bounded_capture.
_bounded_payload() {
  local seconds="$1" rc tmp kind
  shift
  rc=0
  tmp="$(mktemp)"
  kind="$(type -t "$1" 2>/dev/null || true)"
  if [[ "$seconds" -eq 0 ]]; then
    "$@" >"$tmp" 2>/dev/null || rc=$?
  elif [[ "$kind" == "function" ]]; then
    _bounded_background "$seconds" "$tmp" "$@" || rc=$?
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift @ARGV; exec @ARGV' "$seconds" "$@" >"$tmp" 2>/dev/null || rc=$?
  else
    _bounded_background "$seconds" "$tmp" "$@" || rc=$?
  fi
  cat "$tmp"
  # The scan helper's own temp file, not a user store.
  command rm -f "$tmp"
  printf '\n__PRIVACY_SWEEP_RC__=%s\n' "$rc"
}

# run_bounded_capture DEST command...
# Stores stdout in DEST. On SIGALRM (142) or our kill (143), prints the
# timeout line and sets SCAN_TIMED_OUT=1. Does not abort the caller.
run_bounded_capture() {
  local __dest="$1" seconds payload rc body
  shift
  seconds="$(scan_timeout_seconds)"
  SCAN_TIMED_OUT=0
  SCAN_RC=0
  payload="$(_bounded_payload "$seconds" "$@")"
  if [[ "$payload" == *$'\n'__PRIVACY_SWEEP_RC__=* ]]; then
    rc="${payload##*$'\n'__PRIVACY_SWEEP_RC__=}"
    body="${payload%$'\n'__PRIVACY_SWEEP_RC__=*}"
  elif [[ "$payload" == __PRIVACY_SWEEP_RC__=* ]]; then
    rc="${payload#__PRIVACY_SWEEP_RC__=}"
    body=""
  else
    rc=1
    body="$payload"
  fi
  rc="${rc//[^0-9]/}"
  if [[ -z "$rc" ]]; then
    rc=1
  fi
  SCAN_RC="$rc"
  if [[ "$rc" -eq 142 || "$rc" -eq 143 ]]; then
    SCAN_TIMED_OUT=1
    echo "scan timed out after ${seconds}s; partial or skipped"
  fi
  printf -v "$__dest" '%s' "$body"
  return 0
}

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

# missing, readable, or protected. A failed or timed-out ls is protected.
# Prints only the status word. The timeout sentence is left to the caller,
# which reports macOS privacy protection for these folders.
user_dir_status() {
  local path="$1" seconds payload rc
  if [[ ! -d "$path" ]]; then
    printf '%s\n' missing
    return 0
  fi
  seconds="$(scan_timeout_seconds)"
  payload="$(_bounded_payload "$seconds" ls -1 "$path")"
  if [[ "$payload" == *$'\n'__PRIVACY_SWEEP_RC__=* ]]; then
    rc="${payload##*$'\n'__PRIVACY_SWEEP_RC__=}"
  elif [[ "$payload" == __PRIVACY_SWEEP_RC__=* ]]; then
    rc="${payload#__PRIVACY_SWEEP_RC__=}"
  else
    rc=1
  fi
  rc="${rc//[^0-9]/}"
  if [[ -z "$rc" || "$rc" != "0" ]]; then
    printf '%s\n' protected
    return 0
  fi
  printf '%s\n' readable
  return 0
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
# The walk is time-bounded. Do not use this on a File Provider root.
report_dir_summary() {
  local label="$1" path="$2" files="" size="" raw=""
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
  # The single quotes are the child shell's script. $1 is that shell's argument.
  # shellcheck disable=SC2016
  run_bounded_capture raw bash -c 'find -P "$1" -type f 2>/dev/null | wc -l | tr -d " "' bash "$path"
  if [[ "$SCAN_TIMED_OUT" -eq 1 ]]; then
    files="skipped"
  else
    files="${raw//[^0-9]/}"
    files="${files:-0}"
  fi
  raw=""
  run_bounded_capture raw du -sk "$path"
  if [[ "$SCAN_TIMED_OUT" -eq 1 ]]; then
    size=""
  else
    size="$(printf '%s\n' "$raw" | awk '{print $1}' || true)"
  fi
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

# Presence and a depth-1 entry count. No find, no du, no names.
# File Provider and iCloud roots use this so a listing cannot hydrate files.
report_toplevel() {
  local label="$1" path="$2" count=""
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
  # shellcheck disable=SC2016
  run_bounded_capture count bash -c 'ls -1 "$1" 2>/dev/null | wc -l | tr -d " "; exit "${PIPESTATUS[0]}"' bash "$path"
  echo "Present: yes"
  if [[ "$SCAN_TIMED_OUT" -eq 1 ]]; then
    echo "TopLevelEntries: skipped"
  elif [[ "$SCAN_RC" -ne 0 ]]; then
    echo "TopLevelEntries: unreadable"
  else
    count="${count//[^0-9]/}"
    echo "TopLevelEntries: ${count:-0}"
  fi
  echo "This path is not walked. A recursive listing can hydrate cloud files."
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
