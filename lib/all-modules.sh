# shellcheck shell=bash
# Dry-run every module. Sourced by privacy-sweep.sh when --all-modules is set.
# Never passes an apply flag. A non-zero child (SSD refusal, no adb) does not stop the run.

run_step() {
  echo
  echo "===== $1 ====="
  shift
  set +e
  "$@"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "Reported exit $status. Continuing the dry run."
  fi
}

run_all_modules() {
  local os root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  os="${PRIVACY_SWEEP_OS:-$(uname -s)}"
  echo "== Dry run of every module =="
  echo "Host OS for this pass: $os"
  echo "Nothing is deleted. Opt-in tools are planned only. An apply flag is not passed."
  echo "An SSD free-space tool that refuses (exit 2) is reported and does not fail this pass."

  case "$os" in
    Darwin)
      run_step "macOS clear-all" bash "$root/macos/clear-all.sh" --dry-run
      run_step "macOS audit" bash "$root/audit/audit-macos.sh" --dry-run
      # The macOS audit already printed snapshots, Document Revisions, and
      # FileVault. Export is in this process; a child cannot set it for us.
      export PRIVACY_SWEEP_MACOS_RECOVERY_DONE=1
      run_step "APFS snapshots and Document Revisions" bash "$root/recovery-purge/purge-macos.sh" --dry-run --purge-apfs-localsnapshots --purge-document-revisions
      run_step "browser deep stores" bash "$root/browser-deep/clear-browser-deep.sh" --dry-run --clear-browser-deep
      run_step "cloud sync metadata" bash "$root/cloud-sync/audit-cloud.sh" --dry-run
      run_step "persistence" bash "$root/persistence/audit-persistence.sh" --dry-run
      run_step "memory residue" bash "$root/memory-residue/memory.sh" --dry-run --remove-sleepimage
      run_step "local artifacts" bash "$root/local-artifacts/audit-local.sh" --dry-run
      run_step "local artifact clears" bash "$root/local-artifacts/clear-local.sh" --dry-run --all-opt-in
      run_step "macOS free-space note" bash "$root/hdd-free-space/wipe-macos.sh" --dry-run
      ;;
    Linux)
      run_step "Linux clear-all" bash "$root/linux/clear-all.sh" --dry-run
      run_step "Linux audit" bash "$root/audit/audit-linux.sh" --dry-run
      run_step "browser deep stores" bash "$root/browser-deep/clear-browser-deep.sh" --dry-run --clear-browser-deep
      run_step "cloud sync metadata" bash "$root/cloud-sync/audit-cloud.sh" --dry-run
      run_step "persistence" bash "$root/persistence/audit-persistence.sh" --dry-run
      run_step "memory residue" bash "$root/memory-residue/memory.sh" --dry-run --purge-swap
      run_step "local artifacts" bash "$root/local-artifacts/audit-local.sh" --dry-run
      run_step "local artifact clears" bash "$root/local-artifacts/clear-local.sh" --dry-run --all-opt-in
      run_step "Linux free-space fill" bash "$root/hdd-free-space/wipe-linux.sh" --dry-run
      ;;
    *)
      echo "This launcher supports macOS and Linux. Detected: $os."
      echo "On Windows run: .\\privacy-sweep.ps1 -DryRun -AllModules"
      return 0
      ;;
  esac

  run_step "Android permissions" bash "$root/android/audit-permissions.sh" --dry-run
  run_step "Android usage stats" bash "$root/android/audit-usage.sh" --dry-run
  run_step "Android TV packages" bash "$root/android-tv/audit-tv.sh" --dry-run
  echo
  echo "Dry run of every module finished. Nothing was deleted."
}
