# Changelog

## Unreleased

### Added

- `audit/`: report-only recovery structures. Windows shadow-copy counts, Recycle Bin `$I`/`$R` counts, pagefile/hiberfil/MEMORY.DMP presence and size, search-index size, thumbcache database counts, BitLocker protection status. macOS local snapshots, Document Revisions size, external `.Trashes` counts, sleepimage/swap presence, FileVault on/off. Linux swap, LUKS status without keys, and a shallow scan for wipe-tool remnant names. Nothing is deleted, and file contents are not printed.
- `docs/leave-no-trace.md`: the five layers (log less, clear named stores, purge recovery structures, hard-disk free space, encryption and key destruction), why free-space fill on an SSD is not a wipe, the cipher/SDelete/`z` fingerprint names, and why not to plant decoy history entries.
- `hdd-free-space/`: opt-in free-space fill for a hard disk (`cipher /w` on Windows, a fill file on Linux). Dry run first, asks unless `--yes`, refuses SSDs unless `--i-know-this-is-ssd`. Not part of `clear-all`. Does not purge snapshots. macOS is a pointer to the advisory, not a wipe. Purging shadow copies and snapshots is still not in this repo.
- `network/pihole-tv/`: brand-selectable HaGeZi lists (`--brand samsung,lg,roku,firetv`), a keep-list that is allowlisted and never added as a block, and AdGuard Home (`--adguard`) beside Pi-hole for list adds and the ACR client report. Vizio and Hisense stay on the combined lists. The README's first steps are the on-TV ACR settings and a guest network.
- `android-tv/audit-tv.sh`: report-only package list over network `adb`. Flags known telemetry, ad, and content-row packages. Disables nothing, and is not part of `clear-all`.
- `network/pihole-tv/`: add maintained smart-TV and ACR blocklists to a Pi-hole you administer, and report which LAN clients queried those names. List changes are a dry run unless you pass `--ask` or `--yes`. Pi-hole v6 is the HTTP API; v5 can be updated through a local `gravity.db`.
- `network/pihole-report/`: weekly markdown DNS report (top clients, top blocked domains, new clients, ACR hits), plus example cron and systemd timer files.
- `network/router-hygiene/`: checklist for the router admin page, and `check-lan.sh` for the checks a LAN host can actually make.
- `network/device-inventory/`: ARP inventory, with mDNS, SSDP, and `nmap -sn` after you confirm. Flags unnamed devices and TVs on this LAN.
- `audit/`: per-OS report of counts and paths (Prefetch, Jump Lists, USBSTOR, recent items, Wi-Fi profiles, quarantine, Quick Look, thumbnails, shell history). Nothing is deleted.
- `browsers/`: history, cookies, and cache for Chrome, Edge, Firefox, Safari, and Brave. Refuses a browser that is still open. Not part of `clear-all`.
- `android/audit-permissions.sh`: adb report of accessibility, device admin, SMS, call log, notification listeners, and overlay, plus non-Play installs. Removes nothing.
- `forget-wifi` scripts for Windows (`netsh`), macOS (`networksetup`), and Linux (`nmcli`). The network you are using is kept unless you pass `--include-current`.
