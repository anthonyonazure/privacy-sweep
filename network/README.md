# privacy-sweep - your own network

Scripts for a Pi-hole and a LAN you administer. They follow the same three modes as the rest of
the repo, with one difference: **adding blocklists is a dry run until you pass `--ask` or `--yes`**,
because a list change affects every device that uses that resolver.

| Folder | What it is |
| --- | --- |
| [pihole-tv/](pihole-tv/) | Smart-TV / ACR: on-TV settings, then DNS. Brand lists and a keep-list for Pi-hole or AdGuard Home, plus a report of which clients queried those names |
| [pihole-report/](pihole-report/) | Weekly markdown DNS report, with a cron and a systemd timer example |
| [router-hygiene/](router-hygiene/) | Router checklist, plus the few checks a computer on the LAN can make |
| [device-inventory/](device-inventory/) | Who is on this LAN, with TVs and unnamed addresses called out |

Read [SECURITY.md](../SECURITY.md) before you point any of this at a resolver. The password belongs
in `PIHOLE_PASSWORD` or a mode-0600 file named by `PIHOLE_PASSWORD_FILE`, not on the command line
and not in this git repo. AdGuard Home uses `ADGUARD_PASSWORD` or `ADGUARD_PASSWORD_FILE` the
same way, and only when you pass `--adguard`.
