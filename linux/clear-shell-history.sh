#!/usr/bin/env bash
# clear-shell-history.sh - part of privacy-sweep (Linux)
# Clears shell command history (bash, zsh) plus a few interactive-tool histories
# (.viminfo, .lesshst, .python_history). Commands often hold paths and secrets.
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

TARGETS=("$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.viminfo" "$HOME/.lesshst" "$HOME/.python_history")

echo "== Shell & tool command history =="
FOUND=()
for f in "${TARGETS[@]}"; do [[ -f "$f" ]] && FOUND+=("$f"); done
if [[ ${#FOUND[@]} -eq 0 ]]; then echo "No history files found. Nothing to do."; exit 0; fi
printf 'Target: %s\n' "${FOUND[@]}"

if $DRY_RUN; then echo "(dry run) Would truncate the files above to empty."; exit 0; fi
confirm || { echo "Cancelled."; exit 0; }

for f in "${FOUND[@]}"; do : > "$f"; done
echo "Done. History files cleared."
echo "This shell's in-memory history persists; run 'history -c' or open a new terminal."
