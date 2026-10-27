# Changelog

## Unreleased

### Added

- `network/pihole-tv/`: add maintained smart-TV and ACR blocklists to a Pi-hole you administer, and report which LAN clients queried those names. List changes are a dry run unless you pass `--ask` or `--yes`. Pi-hole v6 is the HTTP API; v5 can be updated through a local `gravity.db`.
- `network/pihole-report/`: weekly markdown DNS report (top clients, top blocked domains, new clients, ACR hits), plus example cron and systemd timer files.
- `network/router-hygiene/`: checklist for the router admin page, and `check-lan.sh` for the checks a LAN host can actually make.
- `network/device-inventory/`: ARP inventory, with mDNS, SSDP, and `nmap -sn` after you confirm. Flags unnamed devices and TVs on this LAN.
- `audit/`: per-OS report of counts and paths (Prefetch, Jump Lists, USBSTOR, recent items, Wi-Fi profiles, quarantine, Quick Look, thumbnails, shell history). Nothing is deleted.
- `browsers/`: history, cookies, and cache for Chrome, Edge, Firefox, Safari, and Brave. Refuses a browser that is still open. Not part of `clear-all`.
- `android/audit-permissions.sh`: adb report of accessibility, device admin, SMS, call log, notification listeners, and overlay, plus non-Play installs. Removes nothing.
- `forget-wifi` scripts for Windows (`netsh`), macOS (`networksetup`), and Linux (`nmcli`). The network you are using is kept unless you pass `--include-current`.
