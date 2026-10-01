#!/usr/bin/env bash
# clear-shell-history.sh - part of privacy-sweep (macOS)
# Clears your Terminal command history (zsh and bash), including the second
# copy that Terminal keeps per window in ~/.zsh_sessions.
# Handy because commands can hold paths, hostnames, even secrets typed inline.
# Modes: --dry-run (show only), (default) ask first, --yes (no prompt).
set -euo pipefail

DRY_RUN=false; ASSUME_YES=false
for arg in "$@"; do case "$arg" in
  --dry-run) DRY_RUN=true ;;
  --yes|-y) ASSUME_YES=true ;;
  --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $arg" >&2; exit 1 ;;
esac; done

confirm() { $ASSUME_YES && return 0; read -r -p "Proceed? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

TARGETS=("$HOME/.zsh_history" "$HOME/.bash_history" "$HOME/.zhistory")
# Terminal saves a per-window copy of the history here
shopt -s nullglob
TARGETS+=("$HOME"/.zsh_sessions/*.history "$HOME"/.zsh_sessions/*.historynew)
shopt -u nullglob

echo "== Shell command history =="
FOUND=()
for f in "${TARGETS[@]}"; do [[ -f "$f" ]] && FOUND+=("$f"); done
if [[ ${#FOUND[@]} -eq 0 ]]; then echo "No history files found. Nothing to do."; exit 0; fi
printf 'Target: %s\n' "${FOUND[@]}"

if $DRY_RUN; then echo "(dry run) Would truncate the files above to empty."; exit 0; fi
confirm || { echo "Cancelled."; exit 0; }

for f in "${FOUND[@]}"; do : > "$f"; done
echo "Done. History files cleared."
echo "This session's in-memory history persists until you close the window; run 'history -p' or open a new tab."
