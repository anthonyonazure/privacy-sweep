# Smart-TV and ACR blocking on Pi-hole

Smart TVs use automatic content recognition (ACR) to guess what is on screen and to phone home
about it. Samsung, LG (often via Alphonso), Roku, and Vizio (Inscape) each have their own names.
If the TV uses your Pi-hole for DNS, a blocklist stops the lookup. It does not stop a TV that
uses a hard-coded resolver or DNS-over-HTTPS, and it does not change the setting on the TV itself.

These scripts only talk to a Pi-hole you administer.

## What gets added

[lists.txt](lists.txt) is the catalog. Two lists are proposed every time:

| List | Why it's here |
| --- | --- |
| [Block List Project smart-TV](https://github.com/blocklistproject/Lists) | Hosts-file list, MIT, still updated. The copy checked for this repo carried a header date of 2026-07-06. It includes Samsung ACR, some LG ad hosts, Roku log hosts, and `tvinteractive.tv` (Vizio / Inscape). It does not list `alphonso.tv`. |
| [Perflyst Smart TV](https://github.com/Perflyst/PiHoleBlocklist) | Domain list, MIT, aimed at TV telemetry, including Alphonso and extra Vizio names. Its own version line still says 13July2023, so treat it as a known list, not a fresh one. The file itself warns that apps or updates can stop. |

`--vendor` also offers HaGeZi's Samsung, LG webOS, and Roku tracker lists. Those are maintained
and wider than ACR. They can interfere with accounts, channels, and firmware checks, so they are
off unless you ask. There is no separate maintained Vizio-only URL that returned a file when
these addresses were checked; Vizio coverage is the `tvinteractive.tv` names inside the combined
lists. A Vizio-only HaGeZi URL 404s.

`--alphonso-regex` adds one regex deny, `(^|\.)alphonso\.tv$`, because Alphonso rotates numbered
hosts (`tkacrNNN.alphonso.tv`) and a fixed list goes stale. It is off by default so you can read
it first.

Checked on 2026-10-27: the five URLs in `lists.txt` answered HTTP 200. The publishers can move
them. If Pi-hole later marks a list invalid, remove it in the web UI.

## Modes

```bash
cd network/pihole-tv
chmod +x *.sh
./add-blocklists.sh                 # preview, change nothing
./add-blocklists.sh --ask           # preview, then ask
./add-blocklists.sh --yes           # add the lists and request a gravity update
./add-blocklists.sh --yes --vendor --alphonso-regex
```

To see the plan with no Pi-hole at all:

```bash
./add-blocklists.sh --fixture ../../tests/fixtures/pihole
```

## How it talks to Pi-hole

**v6 (what you want).** Set `PIHOLE_URL` (for example `http://192.168.1.2`, the origin, not
`/admin`) and `PIHOLE_PASSWORD` or `PIHOLE_PASSWORD_FILE`. An application password from the
Pi-hole web UI is the right value. The script logs in with `POST /api/auth`, sends the session
id in `X-FTL-SID`, and adds each missing list with `POST /api/lists?type=block`. Current v6
wants `type` in the query string. If a server answers that it wants `type` in the JSON body
(early v6 did), the script retries once that way. After the adds, it calls
`POST /api/action/gravity` unless you passed `--no-gravity`. The session is closed with
`DELETE /api/auth`.

**v5.** `admin/api.php` can answer summary and top-list reads when `PIHOLE_API_TOKEN` is set.
It has no supported "add this blocklist" call. On the Pi-hole machine, set
`PIHOLE_GRAVITY_DB=/etc/pihole/gravity.db` and the script inserts rows into the `adlist` table,
then tells you to run `pihole -g`. It does not start gravity itself unless that path is the
live database, and even then it only prints the command.

**Reading queries.** `acr-clients.sh` prefers `PIHOLE_FTL_DB` (a copy of `pihole-FTL.db`) because
one SQL query answers "who looked up this name" for the whole window. The `queries` view works
for both the current database, where names are stored as ids, and the older table, where they
are text. If you only have the v6 API, the script searches `/api/queries` per suffix. v5's
`api.php` top lists do not include the client for an ACR name; use the database for that.

Copy a live database without fighting the lock:

```bash
sqlite3 /etc/pihole/pihole-FTL.db ".backup $HOME/pihole-FTL.db.backup"
PIHOLE_FTL_DB=$HOME/pihole-FTL.db.backup ./acr-clients.sh --days 7
```

A self-signed HTTPS certificate needs `PIHOLE_INSECURE=1`. Leave that unset when the certificate
is normal.

## If a TV breaks

Disable that list in the Pi-hole UI (or delete the row) and run gravity again. Streaming that
uses a CDN name you did not mean to block will fail until you do. The report in
[acr-suffixes.txt](acr-suffixes.txt) is a separate, short list of suffixes used only to recognize
lookups. It is not installed as a blocklist. `roku.com` and `samsung.com` are not on it, so
ordinary channel traffic is not reported as ACR.

`acr-clients.sh` only reads. `--output` is the only file it writes, and `--dry-run` skips that.
