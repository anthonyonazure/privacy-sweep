#!/usr/bin/env bash
# Exercise the new scripts on this machine: syntax, shellcheck, dry runs,
# a fake Pi-hole, a fake browser profile, and a fake nmcli.
# Nothing here talks to a real router or a real Pi-hole.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "== bash -n =="
while IFS= read -r script; do
  bash -n "$script"
done < <(find . -name '*.sh' -not -path './.git/*' | sort)

echo "== shellcheck =="
if ! command -v shellcheck >/dev/null 2>&1; then
  fail "shellcheck is not installed"
fi
while IFS= read -r script; do
  shellcheck -x "$script"
done < <(find network audit browsers android linux macos -name '*.sh' | sort)
# The top-level launcher and the original scripts should still parse.
shellcheck -x privacy-sweep.sh

echo "== python =="
python3 -m py_compile network/lib/pihole.py network/lib/lanprobe.py tests/mock_pihole.py tests/test_logic.py
python3 tests/test_logic.py

echo "== pihole fixture dry-run =="
out="$(bash network/pihole-tv/add-blocklists.sh --fixture tests/fixtures/pihole)"
printf '%s\n' "$out" | grep -q "Would add" || fail "fixture plan did not list a list to add"
printf '%s\n' "$out" | grep -q "Perflyst" || fail "Perflyst missing from the plan"
printf '%s\n' "$out" | grep -q "Already on this Pi-hole" || fail "existing list was not recognized"
log="$TMP/applied.json"
bash network/pihole-tv/add-blocklists.sh --fixture tests/fixtures/pihole --yes --apply-log "$log" >/dev/null
python3 - "$log" << 'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt" in data["added"]
assert "https://raw.githubusercontent.com/blocklistproject/Lists/master/smart-tv.txt" not in data["added"]
assert data["gravity"] is True
print("fixture apply ok")
PY

echo "== pihole report fixture =="
report="$(bash network/pihole-report/weekly-report.sh --dry-run --fixture tests/fixtures/pihole)"
printf '%s\n' "$report" | grep -q "living-room-tv" || fail "report missed the TV client"
printf '%s\n' "$report" | grep -q "log-1.samsungacr.com" || fail "report missed an ACR hit"
printf '%s\n' "$report" | grep -q "scribe.logs.roku.com" || fail "report missed a Roku log host"
if printf '%s\n' "$report" | grep -q "old.samsungacr.com"; then
  fail "report included an ACR hit outside the window"
fi
printf '%s\n' "$report" | grep -q "Did not write a report file" || fail "dry-run wrote, or said it did"
state="$TMP/known.txt"
out_md="$TMP/report.md"
bash network/pihole-report/weekly-report.sh --fixture tests/fixtures/pihole --yes --state "$state" --output "$out_md" >/dev/null
[[ -f "$out_md" && -f "$state" ]] || fail "report files were not saved"
python3 - "$state" << 'PY'
import os, stat, sys
mode = stat.S_IMODE(os.stat(sys.argv[1]).st_mode)
assert mode & 0o077 == 0, mode
print("state file mode ok")
PY
second="$(bash network/pihole-report/weekly-report.sh --dry-run --fixture tests/fixtures/pihole --state "$state")"
printf '%s\n' "$second" | grep -q "No client IP in this window was absent" || fail "second run flagged known clients as new"

acr="$(bash network/pihole-tv/acr-clients.sh --dry-run --fixture tests/fixtures/pihole)"
printf '%s\n' "$acr" | grep -q "bedroom-roku" || fail "ACR report missed the Roku client"

echo "== mock Pi-hole v6 =="
python3 tests/mock_pihole.py >"$TMP/port" &
mock_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [[ -s "$TMP/port" ]] && break
  sleep 0.1
done
port="$(head -n 1 "$TMP/port")"
[[ -n "$port" ]] || fail "mock Pi-hole did not print a port"
export PIHOLE_URL="http://127.0.0.1:$port"
export PIHOLE_PASSWORD="test-secret"
unset PIHOLE_PASSWORD_FILE PIHOLE_FTL_DB PIHOLE_GRAVITY_DB PIHOLE_API_TOKEN || true
dry="$(bash network/pihole-tv/add-blocklists.sh)"
printf '%s\n' "$dry" | grep -q "Would add" || fail "live dry-run did not preview"
python3 - "$PIHOLE_URL" << 'PY'
import json, os, sys, urllib.request
base = sys.argv[1]
def get(path, sid=None):
    req = urllib.request.Request(base + path, headers={"X-FTL-SID": sid} if sid else {})
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)
auth = urllib.request.Request(base + "/api/auth", data=json.dumps({"password": "test-secret"}).encode(), headers={"Content-Type": "application/json"})
with urllib.request.urlopen(auth) as resp:
    sid = json.load(resp)["session"]["sid"]
lists = get("/api/lists", sid)
addrs = [row["address"] for row in lists["lists"]]
assert addrs == ["https://raw.githubusercontent.com/blocklistproject/Lists/master/smart-tv.txt"], addrs
print("dry-run did not add a list")
PY
bash network/pihole-tv/add-blocklists.sh --yes --alphonso-regex >/dev/null
python3 - "$PIHOLE_URL" << 'PY'
import json, sys, urllib.request
base = sys.argv[1]
body = json.dumps({"password": "test-secret"}).encode()
req = urllib.request.Request(base + "/api/auth", data=body, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req) as resp:
    sid = json.load(resp)["session"]["sid"]
def get(path):
    req = urllib.request.Request(base + path, headers={"X-FTL-SID": sid})
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)
addrs = [row["address"] for row in get("/api/lists")["lists"]]
assert "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt" in addrs
assert "hagezi" not in " ".join(addrs)
regexes = [row["domain"] for row in get("/api/domains/deny/regex")["domains"]]
assert any("alphonso" in item for item in regexes), regexes
print("v6 apply ok")
PY
api_report="$(bash network/pihole-report/weekly-report.sh --dry-run --days 7)"
printf '%s\n' "$api_report" | grep -q "Pi-hole privacy report" || fail "API report missing header"
printf '%s\n' "$api_report" | grep -q "Pi-hole v6 API" || fail "report did not use the v6 API"
printf '%s\n' "$api_report" | grep -q "log-1.samsungacr.com" || fail "API report missed an ACR hit"
printf '%s\n' "$api_report" | grep -q "living-room-tv" || fail "API report missed the TV name"
if printf '%s\n' "$api_report" | grep -q "old.samsungacr.com"; then
  fail "API report included an ACR hit outside the window"
fi
kill "$mock_pid" 2>/dev/null || true
wait "$mock_pid" 2>/dev/null || true
unset PIHOLE_URL PIHOLE_PASSWORD

echo "== browser sweep =="
fake="$TMP/home"
mkdir -p "$fake/.config/google-chrome/Default/Cache"
mkdir -p "$fake/.mozilla/firefox/abc.default"
printf 'bookmarks-stay\n' > "$fake/.config/google-chrome/Default/Bookmarks"
printf 'history\n' > "$fake/.config/google-chrome/Default/History"
printf 'cookie\n' > "$fake/.config/google-chrome/Default/Cookies"
printf 'cached\n' > "$fake/.config/google-chrome/Default/Cache/payload"
printf '%s\n' '[Profile0]' 'Path=abc.default' > "$fake/.mozilla/firefox/profiles.ini"
python3 - "$fake/.mozilla/firefox/abc.default/places.sqlite" << 'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.executescript("""
CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, foreign_count INTEGER);
CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, place_id INTEGER);
CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, fk INTEGER, title TEXT);
CREATE TABLE moz_inputhistory (place_id INTEGER, input TEXT);
INSERT INTO moz_places VALUES (1, 'https://keep.example/', 1);
INSERT INTO moz_places VALUES (2, 'https://drop.example/', 0);
INSERT INTO moz_bookmarks VALUES (1, 1, 'Keep me');
INSERT INTO moz_historyvisits VALUES (1, 1);
INSERT INTO moz_historyvisits VALUES (2, 2);
""")
con.commit()
PY
printf 'cookie\n' > "$fake/.mozilla/firefox/abc.default/cookies.sqlite"
mkdir -p "$fake/.mozilla/firefox/abc.default/cache2"
printf 'cached\n' > "$fake/.mozilla/firefox/abc.default/cache2/payload"

HOME="$fake" bash browsers/clear-browsers.sh --dry-run --only chrome >/dev/null
[[ -f "$fake/.config/google-chrome/Default/History" ]] || fail "dry-run deleted Chrome history"
HOME="$fake" PRIVACY_SWEEP_ASSUME_OPEN=chrome bash browsers/clear-browsers.sh --yes --only chrome >/dev/null && fail "open Chrome was not refused" || true
status=0
HOME="$fake" PRIVACY_SWEEP_ASSUME_OPEN=chrome bash browsers/clear-browsers.sh --yes --only chrome >/dev/null || status=$?
[[ "$status" -eq 2 ]] || fail "open Chrome exit status was $status"
[[ -f "$fake/.config/google-chrome/Default/History" ]] || fail "open Chrome lost its history"
HOME="$fake" bash browsers/clear-browsers.sh --yes --only chrome,firefox >/dev/null
[[ ! -f "$fake/.config/google-chrome/Default/History" ]] || fail "Chrome history remained"
[[ ! -f "$fake/.config/google-chrome/Default/Cookies" ]] || fail "Chrome cookies remained"
[[ ! -f "$fake/.config/google-chrome/Default/Cache/payload" ]] || fail "Chrome cache remained"
[[ -f "$fake/.config/google-chrome/Default/Bookmarks" ]] || fail "Chrome bookmarks were deleted"
python3 - "$fake/.mozilla/firefox/abc.default/places.sqlite" << 'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
titles = [row[0] for row in con.execute("SELECT title FROM moz_bookmarks")]
assert titles == ["Keep me"], titles
left = [row[0] for row in con.execute("SELECT url FROM moz_places")]
assert left == ["https://keep.example/"], left
assert con.execute("SELECT COUNT(*) FROM moz_historyvisits").fetchone()[0] == 0
print("firefox bookmarks kept")
PY
[[ ! -f "$fake/.mozilla/firefox/abc.default/cookies.sqlite" ]] || fail "Firefox cookies remained"
[[ ! -e "$fake/.mozilla/firefox/abc.default/cache2/payload" ]] || fail "Firefox cache remained"

linkhome="$TMP/linkhome"
mkdir -p "$linkhome/.config/google-chrome/Default" "$TMP/outside"
printf 'secret\n' > "$TMP/outside/secret"
ln -s "$TMP/outside" "$linkhome/.config/google-chrome/Default/Cache"
printf 'h\n' > "$linkhome/.config/google-chrome/Default/History"
HOME="$linkhome" bash browsers/clear-browsers.sh --yes --only chrome >/dev/null
[[ -f "$TMP/outside/secret" ]] || fail "followed a cache symlink outside home"
[[ ! -f "$linkhome/.config/google-chrome/Default/History" ]] || fail "in-home history was not cleared"

echo "== forget-wifi =="
export PATH="$ROOT/tests/fakebin:$PATH"
export NMCLI_LOG="$TMP/nmcli.log"
: > "$NMCLI_LOG"
dry_wifi="$(bash linux/forget-wifi.sh --dry-run)"
printf '%s\n' "$dry_wifi" | grep -q "Would forget: Cafe" || fail "Cafe was not listed"
printf '%s\n' "$dry_wifi" | grep -q "Would forget: My:Net" || fail "escaped nmcli name was parsed wrong"
printf '%s\n' "$dry_wifi" | grep -q "In use, will keep: HomeWifi" || fail "active network was not kept"
[[ ! -s "$NMCLI_LOG" ]] || fail "dry-run deleted a network"
printf 'n\n' | bash linux/forget-wifi.sh >/dev/null
[[ ! -s "$NMCLI_LOG" ]] || fail "answering no still deleted a network"
bash linux/forget-wifi.sh --yes >/dev/null
grep -q "connection delete id Cafe" "$NMCLI_LOG" || fail "Cafe was not deleted"
grep -q "connection delete id My:Net" "$NMCLI_LOG" || fail "My:Net was not deleted"
if grep -q "HomeWifi" "$NMCLI_LOG"; then
  fail "the active network was deleted"
fi
: > "$NMCLI_LOG"
bash linux/forget-wifi.sh --yes --include-current >/dev/null
grep -q "HomeWifi" "$NMCLI_LOG" || fail "include-current did not forget the active network"
unset NMCLI_LOG

echo "== audit is report-only =="
if grep -nE '(^|[^a-zA-Z])(rm|shred|wipe)([^a-zA-Z]|$)' audit/*.sh; then
  fail "audit shell scripts contain a delete command"
fi
sentinel="$HOME/.privacy-sweep-audit-sentinel"
printf 'keep\n' > "$sentinel"
before="$(stat -c %Y "$sentinel")"
bash audit/audit-linux.sh >/dev/null
after="$(stat -c %Y "$sentinel")"
[[ "$before" == "$after" ]] || fail "audit changed a file"
rm -f "$sentinel"
bash audit/audit.sh --dry-run >/dev/null
bash audit/audit-macos.sh >/dev/null && fail "macOS audit ran on Linux" || true
status=0
bash audit/audit-macos.sh >/dev/null || status=$?
[[ "$status" -eq 1 ]] || fail "macOS audit should refuse Linux (status $status)"

fakeh="$TMP/audit-home"
mkdir -p "$fakeh/Pictures/Screenshots" "$fakeh/.config" "$fakeh/.local/share"
printf 'pixels\n' > "$fakeh/Pictures/Screenshots/ignored-name.png"
printf '%s\n' 'XDG_PICTURES_DIR="$HOME/Pictures"' > "$fakeh/.config/user-dirs.dirs"
printf '%s\n' '<bookmark href="file:///secret"></bookmark>' > "$fakeh/.local/share/recently-used.xbel"
report="$(HOME="$fakeh" XDG_CONFIG_HOME="$fakeh/.config" XDG_DATA_HOME="$fakeh/.local/share" XDG_CACHE_HOME="$fakeh/.cache" bash audit/audit-linux.sh)"
printf '%s\n' "$report" | grep -q "Screenshot folders" || fail "screenshot section missing"
printf '%s\n' "$report" | grep -A3 "Path: $fakeh/Pictures/Screenshots" | grep -q "Files: 1" || fail "screenshot count"
if printf '%s\n' "$report" | grep -q "ignored-name"; then
  fail "screenshot file name was printed"
fi
if printf '%s\n' "$report" | grep -q "file:///secret"; then
  fail "recent document URI was printed"
fi
printf '%s\n' "$report" | grep -q "Bookmark entries: 1" || fail "recently-used.xbel was not counted"
printf '%s\n' "$report" | grep -q "systemd journal" || fail "journal section missing"
printf '%s\n' "$report" | grep -q "Journal messages are not printed" || fail "journal note missing"
printf '%s\n' "$report" | grep -q "/var/log/wtmp" || fail "wtmp path missing"
printf '%s\n' "$report" | grep -q "/var/log/lastlog" || fail "lastlog path missing"
printf '%s\n' "$report" | grep -Eq 'no crontab|commands not printed|could not be checked|crontab: not installed' || fail "crontab presence missing"
grep -q 'crontab -l 2>&1 >/dev/null' audit/audit-linux.sh || fail "crontab listing is not discarded"
if grep -nE 'journalctl --' audit/audit-linux.sh | grep -v -- '--disk-usage'; then
  fail "journalctl is used for more than disk usage"
fi
if grep -nE '(^|[[:space:]])last([[:space:]]|$)' audit/audit-linux.sh; then
  fail "audit would run last"
fi
grep -q '/private/var/db/diagnostics' audit/audit-macos.sh || fail "unified log path missing"
grep -q 'knowledgeC.db' audit/audit-macos.sh || fail "knowledgeC path missing"
grep -q '/private/var/db/biome' audit/audit-macos.sh || fail "Biome path missing"
grep -q '/.fseventsd' audit/audit-macos.sh || fail "FSEvents path missing"
if grep -n 'knowledgeC.db' audit/audit-macos.sh | grep -q sqlite3; then
  fail "knowledgeC would be queried"
fi
if grep -n 'log show' audit/audit-macos.sh | grep -v 'does not run'; then
  fail "unified log would be dumped"
fi
for needle in AppCompatCache 'Amcache.hve' 'SRUDB.dat' UserAssist BagMRU 'Services\bam' 'Services\dam'; do
  grep -F -q "$needle" audit/audit-windows.ps1 || fail "windows audit missing $needle"
done
if grep -nE 'reg (export|save|query)|Remove-Item|Set-Content|Out-File' audit/audit-windows.ps1; then
  fail "windows audit would export or write"
fi
grep -q 'What cleaning cannot do' README.md audit/README.md || fail "cleaning limit section missing"
grep -q 'after the program file has been deleted' audit/README.md || fail "execution-store note missing"

echo "== lan dry-run =="
lan="$(bash network/router-hygiene/check-lan.sh --dry-run)"
printf '%s\n' "$lan" | grep -q "Gateway:" || fail "router check missed the gateway line"
printf '%s\n' "$lan" | grep -q "No probe was sent" || fail "dry-run sent or forgot to say it didn't"
inv="$(bash network/device-inventory/inventory.sh --dry-run)"
printf '%s\n' "$inv" | grep -q "LAN inventory" || fail "inventory dry-run produced no report"
printf '%s\n' "$inv" | grep -q "Did not send mDNS" || fail "inventory dry-run was not passive"

echo "== android permission report =="
fix="$TMP/adb"
mkdir -p "$fix"
printf '%s\n' 'com.example.reader/com.example.reader.Service' > "$fix/shell_settings_get_secure_enabled_accessibility_services"
printf '%s\n' 'com.example.reader/com.example.reader.Listener' > "$fix/shell_settings_get_secure_enabled_notification_listeners"
printf '%s\n' 'Enabled Device Admins: com.example.admin' > "$fix/shell_dumpsys_device_policy"
for op in READ_SMS RECEIVE_SMS READ_CALL_LOG WRITE_CALL_LOG PROCESS_OUTGOING_CALLS SYSTEM_ALERT_WINDOW; do
  printf '%s\n' "Uid mode: com.example.reader allow" > "$fix/shell_cmd_appops_query-op_${op}_allow"
done
printf '%s\n' 'package:com.play.app installer=com.android.vending' 'package:com.side.app installer=null' > "$fix/shell_pm_list_packages_-i_-3"
android="$(PRIVACY_SWEEP_ADB_FIXTURE="$fix" bash android/audit-permissions.sh --dry-run)"
printf '%s\n' "$android" | grep -q "com.example.reader" || fail "accessibility service missing"
printf '%s\n' "$android" | grep -q "FLAG    com.side.app" || fail "sideload was not flagged"
printf '%s\n' "$android" | grep -q "play    com.play.app" || fail "Play install was not recognized"
printf '%s\n' "$android" | grep -q "No packages were removed" || fail "report did not say it was read-only"

echo
echo "All local checks passed."
