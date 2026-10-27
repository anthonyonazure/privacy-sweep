# shellcheck shell=bash
# Fixture checks for modules D-J and the Windows dry-run fixes.
# Sourced by test-privacy-sweep.sh. Uses ROOT, TMP, and fail() from that file.

echo "== powershell parse =="
pwsh -NoProfile -NonInteractive -File "$ROOT/tests/parse-ps.ps1"

echo "== unreadable find does not abort a dry run =="
findhome="$TMP/findhome"
mkdir -p "$findhome/Library/Application Support/com.apple.sharedfilelist/locked" "$findhome/.Trash/locked"
printf 'x\n' > "$findhome/Library/Application Support/com.apple.sharedfilelist/locked/keep.sfl2"
printf 'y\n' > "$findhome/.Trash/locked/keep.txt"
chmod 000 "$findhome/Library/Application Support/com.apple.sharedfilelist/locked"
chmod 000 "$findhome/.Trash/locked"
HOME="$findhome" bash "$ROOT/macos/clear-recent.sh" --dry-run >/dev/null
HOME="$findhome" bash "$ROOT/macos/clear-trash.sh" --dry-run >/dev/null
chmod u+rwx "$findhome/Library/Application Support/com.apple.sharedfilelist/locked" "$findhome/.Trash/locked"
chmod -R u+rwx "$findhome"

echo "== wifi profile fixture =="
cat > "$TMP/wlan-test.ps1" << EOF
. '${ROOT}/audit/wlan-names.ps1'
\$names = @(Get-WlanProfileNames -Lines (Get-Content -LiteralPath \$env:PRIVACY_SWEEP_WLAN_FIXTURE))
Write-Output ('Count: ' + \$names.Count)
\$names | ForEach-Object { Write-Output \$_ }
EOF
wlan_out="$(PRIVACY_SWEEP_WLAN_FIXTURE="$ROOT/tests/fixtures/wlan/profiles.txt" pwsh -NoProfile -NonInteractive -File "$TMP/wlan-test.ps1")"
printf '%s\n' "$wlan_out" | grep -q "Count: 6" || fail "wifi fixture count was not 6: $wlan_out"
for name in HomeWifi Cafe Office 'My:Net' Arbeit Casa; do
  printf '%s\n' "$wlan_out" | grep -qx "$name" || fail "wifi fixture missed $name: $wlan_out"
done
if printf '%s\n' "$wlan_out" | grep -q 'null-valued'; then
  fail "wifi parser threw on a null match: $wlan_out"
fi
grep -q "NT AUTHORITY\\\\SYSTEM" "$ROOT/audit/audit-windows.ps1" || fail "USBSTOR SYSTEM ACL wording missing"
if grep -q "Reading USBSTOR often requires an elevated terminal" "$ROOT/audit/audit-windows.ps1"; then
  fail "old USBSTOR elevated sentence is still present"
fi
grep -q "non-interactive logon" "$ROOT/audit/audit-windows.ps1" || fail "HKCU non-interactive note missing"

echo "== recovery audit prints once per process =="
cat > "$TMP/recovery-twice.ps1" << EOF
& '${ROOT}/audit/audit-recovery-windows.ps1'
& '${ROOT}/audit/audit-recovery-windows.ps1'
EOF
dup="$(PRIVACY_SWEEP_RECOVERY_ROOT="$wfix" pwsh -NoProfile -NonInteractive -File "$TMP/recovery-twice.ps1")"
shadows="$(printf '%s\n' "$dup" | grep -c 'Shadow copies: 2' || true)"
[[ "$shadows" -eq 1 ]] || fail "recovery report ran more than once: $dup"
printf '%s\n' "$dup" | grep -q "Skipping the duplicate" || fail "second recovery call did not skip: $dup"
unset PRIVACY_SWEEP_RECOVERY_ROOT

echo "== windows launcher sets LASTEXITCODE =="
code_status=0
code_out=$(pwsh -NoProfile -NonInteractive -Command "& '$ROOT/privacy-sweep.ps1' -DryRun; if (\$null -eq \$global:LASTEXITCODE) { exit 4 }; exit \$global:LASTEXITCODE") || code_status=$?
[[ "$code_status" -eq 0 ]] || fail "privacy-sweep.ps1 -DryRun left LASTEXITCODE unset or non-zero ($code_status): $code_out"
file_status=0
pwsh -NoProfile -NonInteractive -File "$ROOT/privacy-sweep.ps1" -DryRun >/dev/null || file_status=$?
[[ "$file_status" -eq 0 ]] || fail "privacy-sweep.ps1 -File -DryRun exited $file_status"

echo "== all-modules dry run =="
if grep -nE -- '--apply|-Apply' "$ROOT/lib/all-modules.sh" "$ROOT/lib/all-modules.ps1"; then
  fail "all-modules passes an apply flag"
fi
all_status=0
all_out="$(bash "$ROOT/privacy-sweep.sh" --dry-run --all-modules)" || all_status=$?
[[ "$all_status" -eq 0 ]] || fail "linux --all-modules exited $all_status"
printf '%s\n' "$all_out" | grep -q "Dry run of every module finished" || fail "linux all-modules did not finish"
darwin_status=0
darwin_out="$(PRIVACY_SWEEP_OS=Darwin bash "$ROOT/privacy-sweep.sh" --all-modules)" || darwin_status=$?
[[ "$darwin_status" -eq 0 ]] || fail "darwin --all-modules exited $darwin_status"
printf '%s\n' "$darwin_out" | grep -q "forces a dry run" || fail "darwin all-modules did not force a dry run"
win_status=0
win_out="$(pwsh -NoProfile -NonInteractive -File "$ROOT/privacy-sweep.ps1" -AllModules)" || win_status=$?
[[ "$win_status" -eq 0 ]] || fail "windows -AllModules exited $win_status: $win_out"
printf '%s\n' "$win_out" | grep -q "forces a dry run" || fail "windows -AllModules did not force a dry run"
printf '%s\n' "$win_out" | grep -q "Dry run of every module finished" || fail "windows all-modules did not finish"

echo "== module fixtures =="
export PATH="$ROOT/tests/fakebin:$PATH"
export TMUTIL_LOG="$TMP/tmutil-purge.log"
: > "$TMUTIL_LOG"
mhome="$TMP/macos-recovery"
purge_out="$(PRIVACY_SWEEP_OS=Darwin PRIVACY_SWEEP_RECOVERY_ROOT="$mhome" PRIVACY_SWEEP_TMUTIL="$ROOT/tests/fakebin/tmutil" \
  bash "$ROOT/recovery-purge/purge-macos.sh" --dry-run --purge-apfs-localsnapshots --purge-document-revisions)"
printf '%s\n' "$purge_out" | grep -q "Would run: $ROOT/tests/fakebin/tmutil deletelocalsnapshots 2026-10-01-120000" \
  || fail "snapshot purge was not planned: $purge_out"
printf '%s\n' "$purge_out" | grep -q "Dry run: nothing was deleted." || fail "purge dry-run did not stay dry"
[[ -f "$mhome/Users/tester/.DocumentRevisions-V100/Secret Diary.txt" ]] || fail "dry-run removed a document revision"
if grep -q 'deletelocalsnapshots' "$TMUTIL_LOG"; then
  fail "dry-run invoked tmutil delete: $(cat "$TMUTIL_LOG")"
fi
unset TMUTIL_LOG

vss_out="$(PRIVACY_SWEEP_RECOVERY_ROOT="$wfix" pwsh -NoProfile -NonInteractive -File "$ROOT/recovery-purge/purge-vss.ps1" -DryRun -PurgeVss)"
printf '%s\n' "$vss_out" | grep -q "Would run: vssadmin delete shadows /all /quiet" || printf '%s\n' "$vss_out" | grep -q "vssadmin was not found" \
  || fail "vss dry-run did not plan or explain: $vss_out"
printf '%s\n' "$vss_out" | grep -q "Dry run: nothing was deleted." || fail "vss dry-run deleted or said it did"
# The plan line is allowed. The fixture must not have called the fake vssadmin binary.
[[ ! -s "${VSSADMIN_LOG:-$TMP/vssadmin.log}" ]] || fail "vss dry-run invoked vssadmin"

browser_home="$TMP/browser-home"
mkdir -p "$browser_home/.config/google-chrome/Default/IndexedDB/http_example" \
  "$browser_home/.mozilla/firefox/abc.default"
printf 'SECRET-BOOKMARK\n' > "$browser_home/.config/google-chrome/Default/Bookmarks"
printf 'cache\n' > "$browser_home/.config/google-chrome/Default/IndexedDB/http_example/keep"
printf '%s\n' '[Profile0]' 'Path=abc.default' > "$browser_home/.mozilla/firefox/profiles.ini"
printf 'SECRET-PLACES\n' > "$browser_home/.mozilla/firefox/abc.default/places.sqlite"
mkdir -p "$browser_home/.mozilla/firefox/abc.default/storage/default"
printf 'session\n' > "$browser_home/.mozilla/firefox/abc.default/storage/default/row"
browser_status=0
HOME="$browser_home" XDG_CONFIG_HOME="$browser_home/.config" PRIVACY_SWEEP_ASSUME_ANSWER=y \
  bash "$ROOT/browser-deep/clear-browser-deep.sh" --clear-browser-deep --apply --only chrome,firefox >/dev/null || browser_status=$?
[[ "$browser_status" -eq 0 ]] || fail "browser-deep apply exited $browser_status"
[[ -f "$browser_home/.config/google-chrome/Default/Bookmarks" ]] || fail "browser-deep deleted bookmarks"
[[ -f "$browser_home/.mozilla/firefox/abc.default/places.sqlite" ]] || fail "browser-deep deleted places.sqlite"
[[ ! -e "$browser_home/.config/google-chrome/Default/IndexedDB/http_example/keep" ]] || fail "browser IndexedDB was not cleared"
[[ ! -e "$browser_home/.mozilla/firefox/abc.default/storage/default/row" ]] || fail "firefox storage was not cleared"

mailhome="$TMP/mail-home"
mkdir -p "$mailhome/Mail" "$mailhome/Pictures/Screenshots" "$mailhome/.local/share/klipper"
printf 'SECRET-BODY\n' > "$mailhome/Mail/inbox.mbox"
printf 'shot\n' > "$mailhome/Pictures/Screenshots/shot.png"
printf 'clip\n' > "$mailhome/.local/share/klipper/data"
mail_audit="$(PRIVACY_SWEEP_HOME_ROOT="$mailhome" bash "$ROOT/local-artifacts/audit-local.sh" --dry-run)"
if printf '%s\n' "$mail_audit" | grep -q 'SECRET-BODY'; then
  fail "mail audit printed a message body"
fi
printf '%s\n' "$mail_audit" | grep -q "inbox.mbox" || fail "mail path was not reported"
PRIVACY_SWEEP_HOME_ROOT="$mailhome" bash "$ROOT/local-artifacts/clear-local.sh" --dry-run --all-opt-in >/dev/null
[[ -f "$mailhome/Mail/inbox.mbox" ]] || fail "dry-run deleted mail"
[[ -f "$mailhome/Pictures/Screenshots/shot.png" ]] || fail "dry-run deleted a screenshot"
PRIVACY_SWEEP_HOME_ROOT="$mailhome" PRIVACY_SWEEP_ASSUME_ANSWER=y \
  bash "$ROOT/local-artifacts/clear-local.sh" --apply --all-opt-in >/dev/null
[[ -f "$mailhome/Mail/inbox.mbox" ]] || fail "apply deleted mail"
[[ ! -f "$mailhome/Pictures/Screenshots/shot.png" ]] || fail "apply left a screenshot"

cloud="$TMP/cloud"
mkdir -p "$cloud/OneDrive/logs" "$cloud/Dropbox/instance_db" "$cloud/CloudDocs" "$cloud/DriveFS"
printf 'SECRET-TOKEN\n' > "$cloud/OneDrive/logs/sync.log"
printf 'db\n' > "$cloud/OneDrive/SyncEngineDatabase.db"
printf 'SECRET-TOKEN\n' > "$cloud/Dropbox/host.db"
cloud_out="$(PRIVACY_SWEEP_CLOUD_ROOT="$cloud" bash "$ROOT/cloud-sync/audit-cloud.sh" --dry-run)"
printf '%s\n' "$cloud_out" | grep -q "OneDrive logs" || fail "cloud audit missed OneDrive"
if printf '%s\n' "$cloud_out" | grep -q 'SECRET-TOKEN'; then
  fail "cloud audit printed a token"
fi

persist="$TMP/persist"
mkdir -p "$persist/Library/LaunchAgents" "$persist/autostart" "$persist/systemd"
printf 'SECRET-PLIST\n' > "$persist/Library/LaunchAgents/com.example.agent.plist"
printf 'SECRET-EXEC\n' > "$persist/autostart/example.desktop"
printf 'unit\n' > "$persist/loginitems.plist"
persist_out="$(PRIVACY_SWEEP_PERSIST_ROOT="$persist" bash "$ROOT/persistence/audit-persistence.sh" --dry-run)"
printf '%s\n' "$persist_out" | grep -q "com.example.agent.plist" || fail "persistence missed a plist path"
if printf '%s\n' "$persist_out" | grep -q 'SECRET-PLIST\|SECRET-EXEC'; then
  fail "persistence printed file contents"
fi

swapfile="$TMP/swaps"
printf '%s\n' 'Filename Type Size Used Priority' '/swapfile file 1 0 -2' > "$swapfile"
swaplog="$TMP/swap.log"
: > "$swaplog"
PRIVACY_SWEEP_SWAP_FILE="$swapfile" PRIVACY_SWEEP_SWAP_SIMULATE=1 PRIVACY_SWEEP_SWAP_LOG="$swaplog" \
  PRIVACY_SWEEP_CONFIRM='PURGE SWAP' \
  bash "$ROOT/memory-residue/memory.sh" --purge-swap --apply >/dev/null
grep -q swapoff "$swaplog" || fail "swap simulation did not log swapoff"
unset PRIVACY_SWEEP_SWAP_FILE PRIVACY_SWEEP_SWAP_SIMULATE PRIVACY_SWEEP_SWAP_LOG PRIVACY_SWEEP_CONFIRM

usage="$TMP/usage"
mkdir -p "$usage"
printf '%s\n' 'package:com.google.android.apps.wellbeing' 'package:com.example.app' > "$usage/shell_pm_list_packages"
printf '%s\n' 'SECRET-EVENT time=1 pkg=com.example.app' 'another row' > "$usage/shell_dumpsys_usagestats"
usage_out="$(PRIVACY_SWEEP_ADB_FIXTURE="$usage" bash "$ROOT/android/audit-usage.sh" --dry-run)"
printf '%s\n' "$usage_out" | grep -q "present  com.google.android.apps.wellbeing" || fail "usage audit missed wellbeing"
printf '%s\n' "$usage_out" | grep -q "Lines: 2" || fail "usage line count missing: $usage_out"
if printf '%s\n' "$usage_out" | grep -q 'SECRET-EVENT'; then
  fail "usage audit printed an event row"
fi
grep -q "Desktop FOSS cannot replace" "$ROOT/ios/README.md" || fail "iOS acquisition note missing"
[[ -f "$ROOT/docs/reduce-future-logging.md" && -f "$ROOT/docs/anti-forensics.md" ]] || fail "advisory docs missing"

chat="$TMP/chat-home"
mkdir -p "$chat/Slack/Cache" "$chat/Slack/IndexedDB" "$chat/Telegram Desktop/tdata" "$chat/Mail"
printf 'cache\n' > "$chat/Slack/Cache/data"
printf 'SECRET-CHAT\n' > "$chat/Slack/IndexedDB/000.ldb"
printf 'SECRET-CHAT\n' > "$chat/Telegram Desktop/tdata/key"
printf 'SECRET-BODY\n' > "$chat/Mail/archive.pst"
chat_out="$(PRIVACY_SWEEP_HOME_ROOT="$chat" pwsh -NoProfile -NonInteractive -File "$ROOT/local-artifacts/clear-local.ps1" -Apply -ClearChatCaches -Yes)"
[[ ! -f "$chat/Slack/Cache/data" ]] || fail "chat cache was not cleared"
[[ -f "$chat/Slack/IndexedDB/000.ldb" ]] || fail "chat IndexedDB was deleted"
[[ -f "$chat/Telegram Desktop/tdata/key" ]] || fail "telegram tdata was deleted"
[[ -f "$chat/Mail/archive.pst" ]] || fail "mail pst was deleted"
if printf '%s\n' "$chat_out" | grep -q 'SECRET-CHAT\|SECRET-BODY'; then
  fail "chat clear printed a secret"
fi

echo "module fixtures ok"
