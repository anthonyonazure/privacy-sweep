# Smart-TV and ACR blocking

A smart TV can recognize what is on screen (automatic content recognition, ACR) and send that
guess, plus viewing data, to the manufacturer. DNS blocking is the last of three layers. Do
the first two even if you never add a list.

These scripts talk only to a Pi-hole or an AdGuard Home you administer. List changes are a
dry run until you pass `--ask` or `--yes`.

Domain notes below follow [CleanYourTV](https://github.com/Gathin23/cleanyourtv) (MIT), whose
non-Android guide is [cleanyour.tv/not-android](https://cleanyour.tv/not-android). The wording
here is this repo's. Menu paths were taken from that guide (their page said last checked
26 Oct 2026) and were not re-checked on a physical set. Year-by-year screenshots stay on
their site. Where a combined blocklist still contains a name, that was checked by reading
the list files on 2026-10-27.

## 1. Turn ACR off on the TV

Anselmi, Imani, Ladd, and Tyson, in
[Watching TV with the Second-Party](https://arxiv.org/abs/2409.06203) (ACM IMC 2024,
[DOI 10.1145/3646547.3689013](https://doi.org/10.1145/3646547.3689013)), measured Samsung and
LG sets. ACR still ran when the set was used as a "dumb" HDMI display. Signing in or out
did not stop it. Opting out of the on-TV advertising and viewing-information settings
produced no further contact with the ACR domains they had already identified, and no new
ACR domains. That result is for the Samsung and LG sets they measured. It does not cover
Roku, Vizio, Hisense, or Fire TV. Turn the settings off anyway, then use DNS as a backstop.

Menus move every year. If a path below is missing, use the search box in Settings or the
matching year on CleanYourTV.

**Samsung (Tizen).** Turn Viewing Information Services off. On 2025 sets that sits under
Settings, All Settings, General & Privacy, Terms & Privacy. Also turn off interest-based
ads, customization, and "do not track" if those toggles are separate, and reset the
advertising ID. Turn off the Bixby wake word. Use the hardware microphone switch if the set
has one.

**LG (webOS).** Turn Live Plus off. On 2026 sets, hold the Settings button, then System,
Additional settings. On 2021–2024 sets it is under All Settings, General, System, Additional
Settings. Also turn off Viewing Information in the user agreements, turn on limit ad
tracking, and turn off home promotion and content recommendation.

**Roku (TVs, not sticks).** Settings, Privacy, Smart TV Experience, turn ACR off. Older
menus call the same switch "Use info from TV inputs". Under Advertising, turn off ad
personalization. Microphone access is per channel.

**Vizio (SmartCast).** Turn Viewing Data off. The menu is under Privacy & Legal, or Admin
& Privacy, or on older sets System, Reset & Admin. Sets from before 2017 call it Smart
Interactivity. Also turn off the Walmart viewing-data link, turn on limited ad tracking,
and reset the advertiser ID.

**Hisense VIDAA** (some Toshiba sets use the same OS). Turn Enhanced Viewing / ACR off.
The path is Settings, Advanced Settings, Enhanced Viewing Settings, or on VIDAA U5 under
System. Also turn off personalized ads, content recommendation, and the picture/audio
quality toggles that share viewing data. Data-sharing consents live in the same area; a
VIDAA account consent signs you out. Turn off hands-free voice. A Hisense set that runs
Google TV or Roku uses that platform's steps, not these.

**Fire TV.** Settings, Preferences, Privacy Settings: turn off Device Usage Data, Collect
App Usage Data, and Interest-based Ads. Fire TV smart TVs (not the sticks) also have
Over-the-air Viewing Data; turn that off too.

## 2. Put the TV on a guest or IoT network

A TV on the main LAN can see other devices. Put it on guest Wi-Fi or its own VLAN. The
checklist is in [router hygiene](../router-hygiene/README.md).

Google Cast, AirPlay, and similar discovery use mDNS. Guest isolation drops multicast, so
a phone on the main Wi-Fi will not see a TV on the guest network unless the router bridges
mDNS (also called an mDNS repeater, Bonjour forwarding, or an Avahi reflector). Leave that
bridge off unless you need casting and you accept that the two networks will see those
advertisements.

DNS blocking still matters on the guest network: point that network's DNS at your resolver,
or the TV will use whatever resolver it wants.

## 3. Block the names at DNS

`add-blocklists.sh` adds the lists in [lists.txt](lists.txt). Two combined lists are
proposed every time:

| List | Why it's here |
| --- | --- |
| [Block List Project smart-TV](https://github.com/blocklistproject/Lists) | Hosts-file list, MIT. The copy checked for this repo carried a header date of 2026-07-06. It includes Samsung ACR, some LG ad hosts, Roku log hosts, and `tvinteractive.tv` (Vizio / Inscape). It does not list `alphonso.tv`. It still contains several keep-names, which is why the keep-list below is applied on every run. |
| [Perflyst Smart TV](https://github.com/Perflyst/PiHoleBlocklist) | Domain list, MIT, aimed at TV telemetry, including Alphonso. Its own version line still says 13July2023. Commented lines in that file are the keep-names. A few keep-names are still active entries. |

Checked on 2026-10-27, these four HaGeZi lists returned HTTP 200. They are adblock format
(`||name^`), so a name covers its subdomains. A hosts-file line, and a bare domain in
AdGuard, block only that exact host. Pi-hole accepts the adblock URLs as subscribed lists.

| Brand | Flag | URL |
| --- | --- | --- |
| Samsung | `--brand samsung` | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/native.samsung.txt` |
| LG webOS | `--brand lg` | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/native.lgwebos.txt` |
| Roku | `--brand roku` | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/native.roku.txt` |
| Fire TV | `--brand firetv` | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/native.amazon.txt` |

There is no `native.firetv.txt`. The Fire TV flag adds HaGeZi's Amazon list, which also
covers Amazon shopping and video, not only the TV. CleanYourTV's non-Android page has Fire
TV settings and no Fire TV domain keep-table, so this repo does not invent Fire TV keep
names.

Vizio and Hisense have no native list. On 2026-10-27 these URLs returned HTTP 404:
`native.vizio.txt`, `native.vidaa.txt`, `native.hisense.txt`, `native.firetv.txt`.
`--brand vizio` or `--brand hisense` adds no extra URL. Those sets rely on the combined
lists (`tvinteractive.tv` for Vizio / Inscape; the Hisense names those lists already carry).
Do not block all of `vizio.com`, `vidaahub.com`, or `hismarttv.com`.

`--vendor` is the shortcut for `samsung,lg,roku,firetv`. If you pass `--brand` as well,
`--brand` wins.

```bash
cd network/pihole-tv
chmod +x *.sh
./add-blocklists.sh                              # preview, change nothing
./add-blocklists.sh --ask                        # preview, then ask
./add-blocklists.sh --yes                        # combined lists, plus the keep-list
./add-blocklists.sh --yes --brand samsung,lg,roku,firetv
./add-blocklists.sh --yes --brand vizio          # combined lists only; no native URL
./add-blocklists.sh --adguard --yes --brand samsung
```

To see the plan with no resolver at all:

```bash
./add-blocklists.sh --fixture ../../tests/fixtures/pihole
```

`--alphonso-regex` adds one Pi-hole regex deny, `(^|\.)alphonso\.tv$`, because Alphonso
rotates numbered hosts (`tkacrNNN.alphonso.tv`). On AdGuard Home the same flag adds the
adblock rule `||alphonso.tv^`. It is off by default.

## Keep-list

[keep.txt](keep.txt) is the list of names that must keep resolving. Allow rows are written
on every apply, including a run with no `--brand`, because the combined lists already
contain some of them. The script never adds these names as blocks.

- **exact** is this hostname only. On Pi-hole that is an exact allow. On AdGuard it is
  `@@hostname` (a bare exception). A tree exception would also reopen names underneath.
- **tree** is this hostname and its subdomains. On Pi-hole that is a regex allow
  `(^|\.)name$`. On AdGuard it is `@@||name^`.

`samsungcloudsolution.com`, `lgappstv.com`, and `lgtvsdp.com` are exact on purpose.
`acr0.samsungcloudsolution.com` and `ad.lgappstv.com` stay blocked. Pi-hole's gravity
still treats a blocked parent as blocking children that are not themselves allowed, so if
the set still has no internet after the keep-list, turn off the Block List Project and
Perflyst lists in the resolver UI.

`aic-ngfts.lge.com` is not in the keep-list. Content Store images can still fail if that
name is required; allow it from the query log if they do.

Watch rows are printed and not written. `logs.roku.com` is one of them: CleanYourTV says
to block it, and also records one case where the live TV guide went blank until it was
allowed again. The Hisense `auth-*`, `api-gps-*`, `api-launcher-*`, and `msg-*` hosts are
the other watch group (optional; no breakage report). Allow a watch name yourself if that
feature breaks.

## Pi-hole

**v6.** Set `PIHOLE_URL` (the origin, for example `http://192.168.1.2`, not `/admin`) and
`PIHOLE_PASSWORD` or `PIHOLE_PASSWORD_FILE`. An application password is the right value.
The script logs in with `POST /api/auth`, sends `X-FTL-SID`, adds each missing list with
`POST /api/lists?type=block` (and retries once with `type` in the JSON body if the server
asks for that), then writes allow rules with `POST /api/domains/allow/exact` or
`/api/domains/allow/regex`. After that it calls `POST /api/action/gravity` unless you
passed `--no-gravity`. The session is closed with `DELETE /api/auth`.

**v5.** `admin/api.php` can answer summary and top-list reads when `PIHOLE_API_TOKEN` is
set. It has no supported "add this blocklist" call. On the Pi-hole machine, set
`PIHOLE_GRAVITY_DB=/etc/pihole/gravity.db`. The script inserts `adlist` rows and
`domainlist` rows (type 0 exact allow, type 2 regex allow, type 3 regex deny), then tells
you to run `pihole -g`.

## AdGuard Home

Pass `--adguard` (or `--resolver adguard` on the Python helper). Setting `ADGUARD_URL`
without that flag does not switch the scripts. The weekly report stays on Pi-hole.

| Variable | Meaning |
| --- | --- |
| `ADGUARD_URL` | Origin only, for example `http://192.168.1.3:3000` |
| `ADGUARD_USER` | Default `admin` |
| `ADGUARD_PASSWORD` or `ADGUARD_PASSWORD_FILE` | Basic-auth password. Not in the URL, not on the command line. |
| `ADGUARD_INSECURE=1` | Skip TLS verification for a self-signed certificate |

The API is under `/control/`. Filters are added with `POST /control/filtering/add_url`.
User rules are a single document: `POST /control/filtering/set_rules` replaces all of them.
The script reads `GET /control/filtering/status` first and sends the previous rules back
with the new exceptions appended. It does not drop a rule it did not add. It then calls
`POST /control/filtering/refresh`.

Use the adblock copies of the HaGeZi lists. AdGuard's own syntax
([dns filtering](https://adguard-dns.io/kb/general/dns-filtering-syntax/)) treats `||name^`
as the name plus its subdomains, and a simple domain as that host only. `$important` can
beat an exception; the HaGeZi native lists checked on 2026-10-27 do not use it.

`acr-clients.sh --adguard` searches `GET /control/querylog` once per suffix and keeps rows
inside the window. That is a log search, not Pi-hole's long-term database, so the counts
are only what the search returned.

## NextDNS

NextDNS is not configured by these scripts. Two limits matter if you use it for a TV.

The free plan is 300,000 queries a month ([pricing](https://nextdns.io/pricing)). Past that
cap, NextDNS keeps answering and stops blocking, the same as a resolver with no filter.
A TV that is left on can spend the month's quota. The help center says the same about
filtering and logging stopping at the cap.

NextDNS native tracking protection does not cover TV ACR. The domain files in
[nextdns/native-tracking-domains](https://github.com/nextdns/native-tracking-domains/tree/main/domains)
on 2026-10-27 were alexa, apple, huawei, roku, samsung, sonos, windows, and xiaomi.
There was no LG, Vizio, Hisense, or Amazon file. The Samsung file is phone and Knox
metrics (`nmetrics.samsung.com`, `insights.samsung.com`, and similar), not
`samsungacr.com`, `samsungcloud.tv`, or `samsungads.com`. The Roku file is only
`logs.roku.com`. Add the same HaGeZi lists in the NextDNS Blocklists page if you want
TV coverage there.

## Who looked the names up

`acr-clients.sh` only reads. Suffixes live in [acr-suffixes.txt](acr-suffixes.txt). That
file is not installed as a blocklist. `roku.com` and `samsung.com` are not on it.

```bash
./acr-clients.sh --days 7
./acr-clients.sh --dry-run --fixture ../../tests/fixtures/pihole
./acr-clients.sh --adguard --days 7
```

Pi-hole prefers `PIHOLE_FTL_DB` (a copy of `pihole-FTL.db`) because one SQL query answers
the window. Copy a live database without fighting the lock:

```bash
sqlite3 /etc/pihole/pihole-FTL.db ".backup $HOME/pihole-FTL.db.backup"
PIHOLE_FTL_DB=$HOME/pihole-FTL.db.backup ./acr-clients.sh --days 7
```

If you only have the v6 API, the script searches `/api/queries` per suffix. v5's `api.php`
top lists do not include the client for an ACR name; use the database for that.

A self-signed Pi-hole certificate needs `PIHOLE_INSECURE=1`.

## If a TV breaks

Disable that list in the resolver UI and reload gravity or filters. The keep-list is the
set of names this repo will not block on purpose. Anything else that a channel needs can
still be on a maintained list. Allow that one name, or turn the brand list off. Streaming
that uses a CDN name you did not mean to block fails until you do.

Android TV and Google TV package reports, which never disable a package, are
[android-tv/audit-tv.sh](../../android-tv/audit-tv.sh). Reversible disabling and a
replacement launcher are CleanYourTV's, not this repo's.
