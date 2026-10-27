# privacy-sweep

Your computer keeps a surprising amount of history about you: thumbnails of photos you deleted, a
log of every program you ran, lists of files you opened, networks you joined, and things you copied.
Operating systems keep these caches to make everything load faster. The side effect is that the
records survive long after you delete the original file, and most "cleaner" apps only touch a
fraction of them.

**privacy-sweep** is a set of small, readable scripts that clear those stores on your **own**
device. One folder per operating system, one standalone script per store, so you can run just the
one you want or the whole set.

## What this is for

Everyday privacy hygiene: before you sell or donate a machine, after using a shared computer, or
just to keep your data footprint small. This is the same category of tool as
[BleachBit](https://www.bleachbit.org/) and the built-in Windows Disk Cleanup, packaged so you can
see exactly what each script does before you run it.

**Use it only on devices you own or are authorized to administer.** Don't use it to destroy records
you have a legal duty to keep, or on machines that aren't yours.

## Quick start: one command for your OS

There's a top-level launcher that detects your operating system and runs the right full sweep:

```bash
./privacy-sweep.sh --dry-run   # macOS or Linux: preview, delete nothing
./privacy-sweep.sh             # ask before each step
```

```powershell
.\privacy-sweep.ps1 -DryRun    # Windows (run Terminal as Administrator): preview
```

Or go into a platform folder and run a single store's script on its own. Please read
[SECURITY.md](SECURITY.md) first: it's short, and it draws the
line between privacy hygiene (fine) and destroying records you have a duty to keep (not fine).

## How the scripts behave

Every script follows the same three-mode pattern so nothing is deleted by surprise:

| How you run it | What happens |
| --- | --- |
| `./clear-something.sh --dry-run` | Lists exactly what it would clear and how big it is. Deletes nothing. **Start here.** |
| `./clear-something.sh` | Shows the targets, then asks `Proceed? [y/N]` before deleting anything. |
| `./clear-something.sh --yes` | Skips the prompt and clears immediately. For automation and the `clear-all` runner. |

Every script prints what it did. None of them touch anything needed to boot or run the OS, and none
of them require `sudo` unless the folder README says so explicitly.

## Platforms

| Folder | Status | Notes |
| --- | --- | --- |
| [macos/](macos/) | Scripts | Bash. Tested on macOS 26. |
| [windows/](windows/) | Scripts | PowerShell. Run in an elevated terminal for Prefetch. |
| [linux/](linux/) | Scripts | Bash. Works on GNOME/KDE desktops. |
| [ios/](ios/) | Guide | iOS is sandboxed and encrypted; no script can reach these. Manual steps only. |
| [android/](android/) | Guide + partial | Some clearing possible over `adb`; most is manual. A permission report is included. |
| [android-tv/](android-tv/) | Report only | Android TV / Google TV package report over network `adb`. Flags telemetry, ads, and content rows. Disables nothing. |
| [network/](network/) | Scripts + guides | Pi-hole lists and reports, a router checklist, and a LAN inventory. Your own network only. |
| [audit/](audit/) | Report only | Counts and paths of the stores an examiner would look at. Deletes nothing. |
| [browsers/](browsers/) | Scripts | History, cookies, and cache. Opt-in; not part of `clear-all`. |

## Modules beyond the per-OS sweep

The launcher above still runs only the original per-OS clear set. The modules below are
separate because they either talk to your network, only report, or sign you out of things.

| Module | What you run | What it does |
| --- | --- | --- |
| [network/pihole-tv/](network/pihole-tv/) | `add-blocklists.sh`, `acr-clients.sh` | On-TV ACR settings, then brand-selectable blocklists and a keep-list on a Pi-hole or AdGuard Home you administer, and a report of which LAN clients looked those names up. **Dry-run unless you pass `--ask` or `--yes`.** |
| [android-tv/](android-tv/) | `audit-tv.sh` | Over network `adb`, lists installed and enabled packages and flags known telemetry, ad, and content-row packages. **Disables nothing.** Not part of `clear-all`. |
| [network/pihole-report/](network/pihole-report/) | `weekly-report.sh` | Markdown report: top clients, top blocked domains, clients new since last run, ACR hits. Example cron and systemd timer included. |
| [network/router-hygiene/](network/router-hygiene/) | `check-lan.sh` plus the checklist | Admin-password, firmware, UPnP, remote admin, forced DNS, guest Wi-Fi, WPS. The script only checks what a LAN host can see. |
| [network/device-inventory/](network/device-inventory/) | `inventory.sh` | ARP, plus mDNS/SSDP and `nmap -sn` when you allow probes. Flags unnamed devices and TVs on this LAN. |
| [audit/](audit/) | `audit.sh` or `audit-windows.ps1` | Counts and paths, including Windows execution stores, macOS diagnostic and knowledge databases, and Linux journal, login-record, and crontab presence. **Never deletes.** |
| [browsers/](browsers/) | `clear-browsers.sh` / `.ps1` | Chrome, Edge, Firefox, Safari, Brave: history, cookies, cache. Refuses to run while that browser is open. |
| [linux/forget-wifi.sh](linux/forget-wifi.sh), [macos/forget-wifi.sh](macos/forget-wifi.sh), [windows/forget-wifi.ps1](windows/forget-wifi.ps1) | one script per OS | Lists saved Wi-Fi networks, then forgets them. Keeps the network you are using unless you ask. |
| [android/audit-permissions.sh](android/audit-permissions.sh) | over `adb` | Lists accessibility, device-admin, SMS, call-log, notification, and overlay access. Flags installs that did not come from Play. Removes nothing. |

Pi-hole list changes are the one place the default is a dry run rather than a prompt. Everywhere
else, `--dry-run` previews, a plain run asks, and `--yes` skips the prompt. Report-only scripts
accept the same flags and still do not delete.

## What cleaning cannot do

Deleting a file only marks the space as reusable. Until something else is written there, the
previous bytes can still be recovered. The clear scripts do not overwrite free space.

SSDs add another difference. TRIM lets the drive erase discarded blocks when the drive is ready,
so data can vanish sooner than it would on a hard disk, or sit in spare space the OS cannot
point at. A delete you run yourself does not pick which of those happens.

Wiping a file by overwriting it, or editing timestamps so it looks older, leaves its own trace.
Someone comparing the disk can see the overwrite pattern and the clock change.

A missing store can stand out too. No Prefetch, an empty shell history, and an empty journal
do not look like ordinary use. The [audit](audit/) report shows what is still there, including
Windows execution records that can name a program after that program was deleted (ShimCache,
Amcache, SRUM, BAM/DAM, UserAssist, ShellBags), macOS unified logs, knowledgeC, Biome, and
FSEvents, and Linux login-record files. privacy-sweep reports those and does not remove them.
See [SECURITY.md](SECURITY.md).

## The real fix: encryption at rest

Chasing every cache by hand never fully wins, because the system rewrites them as you work. The one
control that covers the entire list at once is **full-disk encryption**: FileVault on macOS,
BitLocker on Windows, LUKS on Linux, and the on-by-default encryption on modern iOS and Android.
When the device is shut down, every one of these stores is unreadable without your password.
These scripts reduce what a *logged-in* session leaves lying around; encryption protects the disk
itself.

## License

MIT. See [LICENSE](LICENSE). No warranty. You are responsible
for what you delete.
