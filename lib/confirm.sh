# shellcheck shell=bash
# Typed and yes/no confirmation for opt-in destructive scripts.
# Source this file. Do not execute it.
# PRIVACY_SWEEP_CONFIRM and PRIVACY_SWEEP_ASSUME_ANSWER are test aids.
# --yes does not satisfy a typed phrase.

confirm_phrase() {
  local phrase="$1" answer=""
  if [[ "${PRIVACY_SWEEP_CONFIRM:-}" == "$phrase" ]]; then
    echo "Confirmation accepted from PRIVACY_SWEEP_CONFIRM (test aid)."
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "Refusing: type exactly: $phrase"
    echo "Nothing was deleted."
    return 1
  fi
  read -r -p "Type ${phrase} to continue: " answer || true
  if [[ "$answer" != "$phrase" ]]; then
    echo "Confirmation did not match. Nothing was deleted."
    return 1
  fi
  return 0
}

confirm_yn() {
  local prompt="$1" answer=""
  if [[ "${PRIVACY_SWEEP_ASSUME_ANSWER:-}" =~ ^[Yy]$ ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "Refusing without a terminal. Nothing was deleted."
    return 1
  fi
  read -r -p "$prompt [y/N] " answer || true
  [[ "$answer" =~ ^[Yy]$ ]]
}
