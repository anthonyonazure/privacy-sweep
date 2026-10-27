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
printf '%s\n' "$win_out" | grep -q "Channel: Application" || fail "event-log plan did not report channel size: $win_out"
printf '%s\n' "$win_out" | grep -q "Would run: wevtutil cl Application" || fail "event-log plan was not wired: $win_out"
printf '%s\n' "$win_out" | grep -q "Windows Search index rebuild plan" || fail "search-index plan was not wired: $win_out"
printf '%s\n' "$win_out" | grep -q "Windows.edb" || fail "search rebuild plan did not name Windows.edb: $win_out"
printf '%s\n' "$win_out" | grep -q "Not installed" || fail "windows all-modules did not say when a browser is missing: $win_out"

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
printf '%s\n' "$vss_out" | grep -q "Shadow copies:" || fail "vss preview did not summarize a count: $vss_out"
printf '%s\n' "$vss_out" | grep -q "Created:" || fail "vss preview did not summarize a creation date: $vss_out"
printf '%s\n' "$vss_out" | grep -q "1.5 GB" || fail "vss preview did not summarize storage: $vss_out"
if printf '%s\n' "$vss_out" | grep -q 'SHOULD-NOT-PRINT\|Shadow Copy ID\|TESTHOST'; then
  fail "vss preview printed raw shadow details: $vss_out"
fi
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
printf 'SECRET-PLIST\n' > "$persist/Library/LaunchAgents/$(printf 'odd.plist\r')"
printf 'SECRET-PLIST\n' > "$persist/Library/LaunchAgents/$(printf 'com.bmad.persona-evolution.plist\r')"
printf 'SECRET-PLIST\n' > "$persist/Library/LaunchAgents/$(printf 'com.bmad.persona-evolution\r.plist')"
printf 'SECRET-EXEC\n' > "$persist/autostart/example.desktop"
printf 'unit\n' > "$persist/loginitems.plist"
persist_out="$(PRIVACY_SWEEP_PERSIST_ROOT="$persist" bash "$ROOT/persistence/audit-persistence.sh" --dry-run)"
printf '%s\n' "$persist_out" | grep -q "com.example.agent.plist" || fail "persistence missed a plist path"
printf '%s\n' "$persist_out" | grep -q -F 'Suspicious name (control character): odd.plist\r' \
  || fail "control character in a launch agent name was not escaped: $persist_out"
printf '%s\n' "$persist_out" | grep -F -x '  Suspicious name (control character): com.bmad.persona-evolution.plist\r' \
  || fail "trailing CR was not escaped once: $persist_out"
printf '%s\n' "$persist_out" | grep -F -x '  Suspicious name (control character): com.bmad.persona-evolution\r.plist' \
  || fail "CR before .plist gained or lost an escape: $persist_out"
if printf '%s\n' "$persist_out" | grep -F -x '  Suspicious name (control character): com.bmad.persona-evolution\r.plist\r'; then
  fail "escaped LaunchAgent name gained a carriage return that is not in the file: $persist_out"
fi
if printf '%s' "$persist_out" | grep -q $'\r'; then
  fail "persistence printed a raw carriage return"
fi
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

echo "== hardware follow-up =="
timeout_out="$(
  # shellcheck source=audit/report-lib.sh
  source "$ROOT/audit/report-lib.sh"
  PRIVACY_SWEEP_SCAN_TIMEOUT=1 run_bounded_capture _junk sleep 5
  printf '%s\n' "TIMED:$SCAN_TIMED_OUT"
)"
printf '%s\n' "$timeout_out" | grep -q "scan timed out after 1s; partial or skipped" || fail "scan timeout message missing: $timeout_out"
printf '%s\n' "$timeout_out" | grep -q "TIMED:1" || fail "scan timeout did not continue: $timeout_out"

child_pidfile="$TMP/scan-child.pid"
rm -f "$child_pidfile"
child_start="$(date +%s)"
child_out="$(
  # shellcheck source=audit/report-lib.sh
  source "$ROOT/audit/report-lib.sh"
  PRIVACY_SWEEP_SCAN_TIMEOUT=1 run_bounded_capture _junk bash -c 'sleep 30 & echo $! > "$1"; wait' _ "$child_pidfile"
  printf 'TIMED:%s\n' "$SCAN_TIMED_OUT"
)"
child_end="$(date +%s)"
child_elapsed="$((child_end - child_start))"
printf '%s\n' "$child_out" | grep -q "TIMED:1" || fail "child scan did not time out: $child_out"
[[ "$child_elapsed" -lt 8 ]] || fail "child scan took ${child_elapsed}s: $child_out"
[[ -s "$child_pidfile" ]] || fail "child pid was not recorded: $child_out"
if kill -0 "$(tr -d '[:space:]' < "$child_pidfile")" 2>/dev/null; then
  fail "timed scan left a child running"
fi

skip_out="$(PRIVACY_SWEEP_MACOS_RECOVERY_DONE=1 PRIVACY_SWEEP_OS=Darwin bash "$ROOT/audit/audit-recovery-macos.sh")"
printf '%s\n' "$skip_out" | grep -q "Skipping the duplicate" || fail "macOS recovery did not skip: $skip_out"
if printf '%s\n' "$skip_out" | grep -q "Local snapshot count"; then
  fail "skipped macOS recovery still printed snapshots: $skip_out"
fi

sleep_out="$(PRIVACY_SWEEP_OS=Darwin PRIVACY_SWEEP_HIBERNATEMODE=3 bash "$ROOT/memory-residue/memory.sh" --dry-run --remove-sleepimage)"
printf '%s\n' "$sleep_out" | grep -q "Would NOT remove (hibernatemode is 3)" || fail "sleepimage plan did not refuse mode 3: $sleep_out"
if printf '%s\n' "$sleep_out" | grep -q 'Would remove:'; then
  fail "sleepimage plan still said it would remove: $sleep_out"
fi

cshome="$TMP/cloudhome"
mkdir -p "$cshome/Library/CloudStorage/OneDrive/nested" \
  "$cshome/Library/CloudStorage/GoogleDrive" \
  "$cshome/Library/Mobile Documents/com~apple~CloudDocs/nested"
printf 'SECRET-NESTED\n' > "$cshome/Library/CloudStorage/OneDrive/nested/secret.dat"
printf 'top\n' > "$cshome/Library/CloudStorage/OneDrive/top.txt"
printf 'SECRET-NESTED\n' > "$cshome/Library/Mobile Documents/com~apple~CloudDocs/nested/secret.dat"
cloud_live="$(HOME="$cshome" PRIVACY_SWEEP_OS=Darwin bash "$ROOT/cloud-sync/audit-cloud.sh" --dry-run)"
printf '%s\n' "$cloud_live" | grep -q "TopLevelEntries:" || fail "cloud provider root was not a top-level count: $cloud_live"
if printf '%s\n' "$cloud_live" | grep -q 'SECRET-NESTED\|SizeKiB:'; then
  fail "cloud provider root was walked or sized: $cloud_live"
fi

ph="$TMP/prunehome"
mkdir -p "$ph/Library/CloudStorage/OneDrive" "$ph/Library/Mobile Documents" \
  "$ph/node_modules" "$ph/captures" "$ph/Mail"
printf 'x\n' > "$ph/Library/CloudStorage/secret.pcap"
printf 'x\n' > "$ph/Library/CloudStorage/OneDrive/nested.pcap"
printf 'x\n' > "$ph/Library/Mobile Documents/icloud.pcap"
printf 'x\n' > "$ph/node_modules/hidden.pcap"
printf 'x\n' > "$ph/captures/a.pcap"
printf 'SECRET-BODY\n' > "$ph/Mail/inbox.mbox"
printf 'x\n' > "$ph/.DS_Store"
mkdir -p "$ph/Library/Caches" "$ph/project/.git"
printf 'x\n' > "$ph/Library/Caches/.DS_Store"
printf 'x\n' > "$ph/node_modules/.DS_Store"
printf 'x\n' > "$ph/project/.git/.DS_Store"
prune_out="$(PRIVACY_SWEEP_HOME_ROOT="$ph" PRIVACY_SWEEP_SCAN_TIMEOUT=5 bash "$ROOT/local-artifacts/audit-local.sh" --dry-run)"
printf '%s\n' "$prune_out" | grep -q "captures" || fail "readable capture dir was not reported: $prune_out"
printf '%s\n' "$prune_out" | grep -q "inbox.mbox" || fail "mail outside a provider root was not reported: $prune_out"
if printf '%s\n' "$prune_out" | grep -q 'secret.pcap\|nested.pcap\|icloud.pcap\|hidden.pcap\|SECRET-BODY'; then
  fail "home scan entered a pruned directory or printed mail: $prune_out"
fi
ds_section="$(printf '%s\n' "$prune_out" | sed -n '/-- \.DS_Store count --/,/^$/p')"
printf '%s\n' "$ds_section" | grep -q 'Files: 1' || fail "DS_Store count was not 1: $ds_section"

desk="$TMP/deskhome"
mkdir -p "$desk/Desktop" "$desk/Documents" "$desk/Downloads"
chmod 755 "$TMP" "$desk"
chmod 000 "$desk/Desktop"
desk_cmd="PRIVACY_SWEEP_HOME_ROOT='$desk' PRIVACY_SWEEP_SCAN_TIMEOUT=3 bash '$ROOT/local-artifacts/audit-local.sh' --dry-run"
desk_status=0
if [[ "$(id -u)" -eq 0 ]] && id nobody >/dev/null 2>&1; then
  desk_out="$(su nobody -s /bin/bash -c "$desk_cmd")" || desk_status=$?
else
  desk_out="$(bash -c "$desk_cmd")" || desk_status=$?
fi
[[ "$desk_status" -eq 0 ]] || fail "protected-folder audit exited $desk_status: $desk_out"
printf '%s\n' "$desk_out" | grep -q "not readable from this session (macOS privacy protection)" \
  || fail "protected Desktop was not reported: $desk_out"
chmod 755 "$desk/Desktop"

# report_keep is the helper Safari uses for Bookmarks.plist. Chrome hits it here
# so the unreadable-file check runs on Linux as well as macOS.
bmhome="$TMP/bookmarks-home"
mkdir -p "$bmhome/.config/google-chrome/Default" "$bmhome/Library/Safari"
printf 'secret-bookmark\n' > "$bmhome/.config/google-chrome/Default/Bookmarks"
printf 'secret-bookmark\n' > "$bmhome/Library/Safari/Bookmarks.plist"
chmod 755 "$TMP" "$bmhome" "$bmhome/.config" "$bmhome/.config/google-chrome" \
  "$bmhome/.config/google-chrome/Default" "$bmhome/Library" "$bmhome/Library/Safari"
chmod 000 "$bmhome/.config/google-chrome/Default/Bookmarks" "$bmhome/Library/Safari/Bookmarks.plist"
bm_err="$TMP/bm.err"
bm_cmd="HOME='$bmhome' XDG_CONFIG_HOME='$bmhome/.config' bash '$ROOT/browser-deep/clear-browser-deep.sh' --dry-run --only chrome"
bm_status=0
if [[ "$(id -u)" -eq 0 ]] && id nobody >/dev/null 2>&1; then
  bm_out="$(su nobody -s /bin/bash -c "$bm_cmd" 2>"$bm_err")" || bm_status=$?
else
  bm_out="$(bash -c "$bm_cmd" 2>"$bm_err")" || bm_status=$?
fi
[[ "$bm_status" -eq 0 ]] || fail "bookmark readability probe exited $bm_status: $bm_out"
printf '%s\n' "$bm_out" | grep -q "present (not readable: macOS privacy protection)" \
  || fail "unreadable bookmarks were not reported: $bm_out"
if grep -Ei 'permission denied|operation not permitted' "$bm_err"; then
  fail "bookmarks probe leaked an open error: $(cat "$bm_err")"
fi
chmod 644 "$bmhome/.config/google-chrome/Default/Bookmarks" "$bmhome/Library/Safari/Bookmarks.plist"

edgehome="$TMP/edge-home"
mkdir -p "$edgehome/.config/microsoft-edge/Default"
edge_status=0
edge_out="$(HOME="$edgehome" XDG_CONFIG_HOME="$edgehome/.config" PRIVACY_SWEEP_ASSUME_OPEN=edge \
  bash "$ROOT/browser-deep/clear-browser-deep.sh" --dry-run --clear-browser-deep --only edge)" || edge_status=$?
[[ "$edge_status" -eq 2 ]] || fail "running Edge should exit 2, got $edge_status: $edge_out"
printf '%s\n' "$edge_out" | grep -q "Quit Edge" || fail "running browser was not named: $edge_out"

agent_hits="$(printf '%s\n' "$persist_out" | grep -c 'com.example.agent.plist' || true)"
[[ "$agent_hits" -eq 1 ]] || fail "launch agent listed $agent_hits times: $persist_out"
login_out="$(PRIVACY_SWEEP_OS=Darwin HOME="$TMP/login-home" bash "$ROOT/persistence/audit-persistence.sh" --dry-run)"
printf '%s\n' "$login_out" | grep -q "does not use sudo" || fail "sfltool note missing: $login_out"
printf '%s\n' "$login_out" | grep -q "/private/var/db/com.apple.backgroundtaskmanagement" || fail "system BTM path missing: $login_out"
mkdir -p "$TMP/login-home/Library/Application Support/com.apple.backgroundtaskmanagementagent"
printf 'binary\n' > "$TMP/login-home/Library/Application Support/com.apple.backgroundtaskmanagementagent/backgrounditems.btm"
login_btm="$(PRIVACY_SWEEP_OS=Darwin HOME="$TMP/login-home" bash "$ROOT/persistence/audit-persistence.sh" --dry-run)"
printf '%s\n' "$login_btm" | grep -q "backgrounditems.btm" || fail "user BTM path missing: $login_btm"
printf '%s\n' "$login_btm" | grep -q "Present: yes (binary; not decoded)" || fail "user BTM was not reported: $login_btm"

ffhome="$TMP/ffhome"
mkdir -p "$ffhome/AppData/Local/Google/Chrome/User Data/Default" \
  "$ffhome/AppData/Local/Google/Chrome/User Data/Profile 1" \
  "$ffhome/AppData/Local/Microsoft/Edge/User Data/Default" \
  "$ffhome/AppData/Roaming/Mozilla/Firefox/Profiles/abc.default"
printf '%s\n' '[Profile0]' 'Name=default' 'IsRelative=1' 'Path=Profiles/abc.default' \
  > "$ffhome/AppData/Roaming/Mozilla/Firefox/profiles.ini"
browser_win="$(PRIVACY_SWEEP_ASSUME_OPEN=edge pwsh -NoProfile -NonInteractive -Command '
  Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_HOME_ROOT -ErrorAction SilentlyContinue
  $env:USERPROFILE = "'"$ffhome"'"
  & "'"$ROOT"'/browser-deep/clear-browser-deep.ps1" -DryRun -ClearBrowserDeep
')"
printf '%s\n' "$browser_win" | grep -q "Profile 1" || fail "Chrome profile discovery missed Profile 1: $browser_win"
printf '%s\n' "$browser_win" | grep -q "abc.default" || fail "Firefox profiles.ini was not read: $browser_win"
printf '%s\n' "$browser_win" | grep -q "Not installed" || fail "missing browser was not reported: $browser_win"
printf '%s\n' "$browser_win" | grep -q "Quit Edge" || fail "running Edge was not named on Windows: $browser_win"

odhome="$TMP/odhome"
mkdir -p "$odhome/OneDrive - Contoso/deep" \
  "$odhome/AppData/Local/Microsoft/OneDrive/logs/Business1" \
  "$odhome/AppData/Local/Microsoft/OneDrive/logs/Personal"
printf 'SECRET-FILE\n' > "$odhome/OneDrive - Contoso/deep/SECRET-FILE"
printf 'log\n' > "$odhome/AppData/Local/Microsoft/OneDrive/logs/Business1/sync.log"
od_out="$(PRIVACY_SWEEP_HOME_ROOT="$odhome" pwsh -NoProfile -NonInteractive -File "$ROOT/cloud-sync/audit-cloud.ps1" -DryRun)"
printf '%s\n' "$od_out" | grep -q "TopLevelEntries:" || fail "Windows cloud root was not top-level: $od_out"
printf '%s\n' "$od_out" | grep -q "OneDrive logs Business1" || fail "Business1 logs were not checked: $od_out"
printf '%s\n' "$od_out" | grep -q "OneDrive logs Personal" || fail "Personal logs were not checked: $od_out"
if printf '%s\n' "$od_out" | grep -q 'SECRET-FILE'; then
  fail "Windows cloud audit walked a nested OneDrive file: $od_out"
fi

echo "== round 3 =="
bad_ps="$TMP/bad-auto.ps1"
good_ps="$TMP/good-auto.ps1"
cat > "$bad_ps" <<'EOF'
$home = 'x'
foreach ($profile in @('a')) {}
$pid = 1
$host = 'h'
$input = 1
EOF
cat > "$good_ps" <<'EOF'
$userHome = 'x'
foreach ($browserProfile in @('a')) {}
$null = 'discard'
$profilePath = 'p'
$env:HOME = 'e'
EOF
auto_status=0
auto_out="$(pwsh -NoProfile -NonInteractive -Command "
  . '$ROOT/tests/parse-ps.ps1'
  \$bad = Test-AutomaticVariableAssignment '$bad_ps'
  \$good = Test-AutomaticVariableAssignment '$good_ps'
  Write-Host \"BAD:\$bad\"
  Write-Host \"GOOD:\$good\"
  if (\$bad -lt 5) { exit 1 }
  if (\$good -ne 0) { exit 1 }
")" || auto_status=$?
[[ "$auto_status" -eq 0 ]] || fail "automatic variable lint failed: $auto_out"
printf '%s\n' "$auto_out" | grep -q 'BAD:5' || fail "expected 5 automatic assignments: $auto_out"

users="$TMP/Users"
empty="$users/anthony.incomplete"
antho="$users/antho"
mkdir -p "$empty" \
  "$antho/AppData/Local/Google/Chrome/User Data/Default/IndexedDB" \
  "$antho/AppData/Local/Microsoft/Edge/User Data/Default" \
  "$antho/AppData/Roaming/Mozilla/Firefox/Profiles/abc.default" \
  "$antho/OneDrive - Contoso/deep" \
  "$users/Public/AppData/Local/Google/Chrome/User Data/Default"
printf 'x\n' > "$antho/AppData/Local/Google/Chrome/User Data/Default/IndexedDB/keep.ldb"
printf '%s\n' '[Profile0]' 'Name=default' 'IsRelative=1' 'Path=Profiles/abc.default' \
  > "$antho/AppData/Roaming/Mozilla/Firefox/profiles.ini"
printf 'SECRET-FILE\n' > "$antho/OneDrive - Contoso/deep/SECRET-FILE"
sib_out="$(pwsh -NoProfile -NonInteractive -Command '
  Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_HOME_ROOT -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_CLOUD_ROOT -ErrorAction SilentlyContinue
  $env:USERPROFILE = "'"$empty"'"
  & "'"$ROOT"'/browser-deep/clear-browser-deep.ps1" -DryRun -ClearBrowserDeep
  & "'"$ROOT"'/cloud-sync/audit-cloud.ps1" -DryRun
')"
printf '%s\n' "$sib_out" | grep -q 'antho:' || fail "sibling profile was not named: $sib_out"
printf '%s\n' "$sib_out" | grep -q 'Chrome profiles' || fail "sibling chrome count missing: $sib_out"
printf '%s\n' "$sib_out" | grep -q 'Re-run as that user.' || fail "sibling re-run note missing: $sib_out"
printf '%s\n' "$sib_out" | grep -q -- '-ProfilePath' || fail "ProfilePath suggestion missing: $sib_out"
if printf '%s\n' "$sib_out" | grep -q 'SECRET-FILE\|Contoso\|Public:'; then
  fail "sibling note leaked a name it should not print: $sib_out"
fi
if printf '%s\n' "$sib_out" | grep -q 'Cannot overwrite variable HOME'; then
  fail "cloud-sync still assigns HOME: $sib_out"
fi

keep="$antho/AppData/Local/Google/Chrome/User Data/Default/IndexedDB/keep.ldb"
pp_out="$(pwsh -NoProfile -NonInteractive -Command '
  Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_HOME_ROOT -ErrorAction SilentlyContinue
  $env:USERPROFILE = "'"$empty"'"
  & "'"$ROOT"'/browser-deep/clear-browser-deep.ps1" -DryRun -ClearBrowserDeep -ProfilePath "'"$antho"'"
')"
printf '%s\n' "$pp_out" | grep -q "another user's profile" || fail "foreign profile warning missing: $pp_out"
printf '%s\n' "$pp_out" | grep -q 'IndexedDB' || fail "ProfilePath did not plan the other profile: $pp_out"
if printf '%s\n' "$pp_out" | grep -q 'An elevated dry run can pass -ProfilePath'; then
  fail "ProfilePath run still recommended the profile it is already auditing: $pp_out"
fi
[[ -f "$keep" ]] || fail "dry-run deleted another user's IndexedDB"
pp_apply="$(PRIVACY_SWEEP_ASSUME_ANSWER=n pwsh -NoProfile -NonInteractive -Command '
  Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_HOME_ROOT -ErrorAction SilentlyContinue
  $env:USERPROFILE = "'"$empty"'"
  & "'"$ROOT"'/browser-deep/clear-browser-deep.ps1" -Apply -ClearBrowserDeep -ProfilePath "'"$antho"'"
')"
[[ -f "$keep" ]] || fail "declined confirmation deleted another user's IndexedDB: $pp_apply"
printf '%s\n' "$pp_apply" | grep -q 'Cancelled' || fail "declined confirmation did not cancel: $pp_apply"
PRIVACY_SWEEP_ASSUME_ANSWER=y pwsh -NoProfile -NonInteractive -Command '
  Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_HOME_ROOT -ErrorAction SilentlyContinue
  $env:USERPROFILE = "'"$empty"'"
  & "'"$ROOT"'/browser-deep/clear-browser-deep.ps1" -Apply -ClearBrowserDeep -ProfilePath "'"$antho"'"
' >/dev/null
[[ ! -f "$keep" ]] || fail "confirmed apply left another user's IndexedDB"
unset PRIVACY_SWEEP_ASSUME_ANSWER

cloud_pp="$(pwsh -NoProfile -NonInteractive -Command '
  Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_HOME_ROOT -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_CLOUD_ROOT -ErrorAction SilentlyContinue
  $env:USERPROFILE = "'"$empty"'"
  & "'"$ROOT"'/cloud-sync/audit-cloud.ps1" -DryRun -ProfilePath "'"$antho"'"
')"
printf '%s\n' "$cloud_pp" | grep -q 'OneDrive root' || fail "ProfilePath cloud audit missed OneDrive: $cloud_pp"
printf '%s\n' "$cloud_pp" | grep -q 'antho' || fail "ProfilePath cloud audit missed the profile: $cloud_pp"
if printf '%s\n' "$cloud_pp" | grep -q 'SECRET-FILE'; then
  fail "ProfilePath cloud audit printed a nested file: $cloud_pp"
fi
if printf '%s\n' "$cloud_pp" | grep -q 'An elevated dry run can pass -ProfilePath'; then
  fail "cloud ProfilePath run still recommended that profile: $cloud_pp"
fi

dscl="$TMP/ds-clear"
mkdir -p "$dscl/Library/Caches" "$dscl/node_modules" "$dscl/project/.git" "$dscl/Desktop"
printf 'x\n' > "$dscl/.DS_Store"
printf 'x\n' > "$dscl/Library/Caches/.DS_Store"
printf 'x\n' > "$dscl/node_modules/.DS_Store"
printf 'x\n' > "$dscl/project/.git/.DS_Store"
printf 'keep\n' > "$dscl/keep.txt"
ds_clear="$(PRIVACY_SWEEP_HOME_ROOT="$dscl" PRIVACY_SWEEP_SCAN_TIMEOUT=5 bash "$ROOT/local-artifacts/clear-local.sh" --dry-run --clear-ds-store)"
ds_section="$(printf '%s\n' "$ds_clear" | sed -n '/-- \.DS_Store --/,/^$/p')"
printf '%s\n' "$ds_section" | grep -q 'Files: 1' || fail "clear-local DS_Store count was not 1: $ds_section"
[[ -f "$dscl/Library/Caches/.DS_Store" && -f "$dscl/.DS_Store" ]] || fail "dry-run removed a .DS_Store"
PRIVACY_SWEEP_HOME_ROOT="$dscl" PRIVACY_SWEEP_SCAN_TIMEOUT=5 \
  bash "$ROOT/local-artifacts/clear-local.sh" --apply --clear-ds-store >/dev/null
[[ ! -f "$dscl/.DS_Store" ]] || fail "apply left the home .DS_Store"
[[ -f "$dscl/Library/Caches/.DS_Store" ]] || fail "apply deleted a Library .DS_Store"
[[ -f "$dscl/node_modules/.DS_Store" && -f "$dscl/project/.git/.DS_Store" ]] || fail "apply deleted a pruned .DS_Store"
[[ -f "$dscl/keep.txt" ]] || fail "apply deleted an unrelated file"

u2="$TMP/round4/Users"
sess="$u2/anthony.incomplete"
other="$u2/antho"
mkdir -p "$sess/OneDrive" \
  "$other/OneDrive - Contoso/deep" \
  "$other/AppData/Local/Microsoft/OneDrive/settings/Business1"
printf 'SECRET-FILE\n' > "$other/OneDrive - Contoso/deep/SECRET-FILE"
printf 'libraryFolder=C:\\Users\\antho\\Sites\\SecretOrg\n' \
  > "$other/AppData/Local/Microsoft/OneDrive/settings/Business1/scope.ini"
biz_out="$(pwsh -NoProfile -NonInteractive -Command '
  Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_HOME_ROOT -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_CLOUD_ROOT -ErrorAction SilentlyContinue
  $env:USERPROFILE = "'"$sess"'"
  & "'"$ROOT"'/cloud-sync/audit-cloud.ps1" -DryRun
')"
printf '%s\n' "$biz_out" | grep -q 'OneDrive for Business roots 1' || fail "business roots on another profile were skipped: $biz_out"
printf '%s\n' "$biz_out" | grep -q 'SharePoint roots 1' || fail "SharePoint roots on another profile were skipped: $biz_out"
printf '%s\n' "$biz_out" | grep -q 'no OneDrive for Business or SharePoint roots' || fail "business gap was not explained: $biz_out"
if printf '%s\n' "$biz_out" | grep -q 'SECRET-FILE\|Contoso\|SecretOrg'; then
  fail "business note leaked a folder or library name: $biz_out"
fi
biz_pp="$(pwsh -NoProfile -NonInteractive -Command '
  Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_HOME_ROOT -ErrorAction SilentlyContinue
  Remove-Item Env:PRIVACY_SWEEP_CLOUD_ROOT -ErrorAction SilentlyContinue
  $env:USERPROFILE = "'"$sess"'"
  & "'"$ROOT"'/cloud-sync/audit-cloud.ps1" -DryRun -ProfilePath "'"$other"'"
')"
if printf '%s\n' "$biz_pp" | grep -q 'An elevated dry run can pass -ProfilePath'; then
  fail "ProfilePath run recommended the profile it already targets: $biz_pp"
fi
if printf '%s\n' "$biz_pp" | grep -q 'SECRET-FILE\|SecretOrg'; then
  fail "ProfilePath cloud audit printed a library path or nested file: $biz_pp"
fi

echo "module fixtures ok"
