# LAN device inventory

`inventory.sh` lists who is on the LAN this computer is joined to, then calls out two things:
addresses with no name from anywhere, and devices that look like TVs. A TV in that list is on
this network, not on a guest VLAN this computer cannot see. Run it from the main LAN when you
want to know whether a TV is sitting there.

```bash
cd network/device-inventory
chmod +x inventory.sh
./inventory.sh --dry-run     # ARP table only; no probes
./inventory.sh               # show that, then ask before probing
./inventory.sh --yes
```

The full run adds:

- mDNS, via `avahi-browse` when it is installed, otherwise a few direct queries to `224.0.0.251`
- one SSDP M-SEARCH, the same discovery TVs use to announce themselves
- `nmap -sn` of this host's IPv4 subnet, when nmap is installed and the prefix is /22 or tighter

Names from Pi-hole are merged in when `PIHOLE_URL` and `PIHOLE_PASSWORD` are set, or when
`PIHOLE_FTL_DB` points at a database copy. See [../pihole-tv/README.md](../pihole-tv/README.md).
The v6 call is `GET /api/network/devices`. v5 has no equivalent; use the database.

A device is marked **likely-tv** when its name or discovery banner looks like a Roku, webOS,
Tizen, Bravia, Chromecast, Fire TV, Vizio, or similar. **possible-vendor** means Pi-hole's
vendor string is a company that makes TVs, and the name did not look like a phone. Phones from
those companies are not labeled as TVs. Both checks are hints.

The gateway is not called unknown just because it has no mDNS name.
