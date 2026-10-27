# Weekly Pi-hole privacy report

`weekly-report.sh` prints a markdown report for the last seven days (change it with `--days`):

- how many queries were stored, and how many were blocked
- the busiest clients
- the most-blocked domains
- client IPs that were not in the previous saved run
- lookups that match the ACR suffixes in [../pihole-tv/acr-suffixes.txt](../pihole-tv/acr-suffixes.txt)

The first saved run is a baseline: everybody seen that week is remembered and nobody is called
new. Later runs list only addresses that were absent from that file. The file lives under
`${XDG_STATE_HOME:-$HOME/.local/state}/privacy-sweep/` unless you pass `--state`, and it is
written mode 0600. The report does not delete queries and does not change blocklists.

```bash
cd network/pihole-report
chmod +x weekly-report.sh
./weekly-report.sh --dry-run
./weekly-report.sh --yes --output "$HOME/pihole-privacy.md"
```

Credentials are the same as [../pihole-tv/README.md](../pihole-tv/README.md). A readable
`PIHOLE_FTL_DB` is the best source. The v6 API uses `/api/stats/database/summary`,
`/api/history/database/clients` (totals, not only the allowed half of the top-client call),
`/api/stats/database/top_domains?blocked=true`, and `/api/queries` for the ACR section.
v5 `api.php` only has a short rolling top list and cannot attribute an ACR name to a client;
the report says so when that is the source.

Try it with no Pi-hole:

```bash
./weekly-report.sh --dry-run --fixture ../../tests/fixtures/pihole
```

## Running it every week

Edit the paths in [pihole-report.cron.example](pihole-report.cron.example), then `crontab -e`.

Or install the pair of unit files, after editing `ExecStart` and `EnvironmentFile` in
[pihole-report.service](pihole-report.service):

```bash
sudo cp pihole-report.service pihole-report.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pihole-report.timer
```

The environment file should look like this, mode 0600, and it should not be committed:

```
PIHOLE_URL=http://192.168.1.2
PIHOLE_PASSWORD_FILE=/etc/privacy-sweep/pihole.password
```

`--yes` is what makes the timer actually save. Without it the script prints a preview and
leaves the known-client file alone.
