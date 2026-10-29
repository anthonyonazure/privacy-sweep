# Router hygiene

Do this in the router's own admin page, on a router you own. `check-lan.sh` cannot see most of
it. A tick here is you, looking at the page.

## Checklist

- [ ] **Admin password changed.** Not the sticker password, and not a password you use anywhere else.
- [ ] **Firmware current.** Apply the update the vendor is actually shipping, then come back and confirm the version changed.
- [ ] **UPnP off.** UPnP lets a device ask the router to open a port toward the internet. Turn it off unless you have a specific reason and you know which device needs it.
- [ ] **WAN / remote management off.** No admin page on the internet side, no "manage from anywhere" cloud toggle you do not use, no TR-069 / ISP remote support left on if the router lets you disable it.
- [ ] **DNS forced to Pi-hole.** DHCP should hand out only the Pi-hole. In the firewall, block or redirect outbound DNS (port 53) that is not going to the Pi-hole, or a TV can ignore DHCP and use `8.8.8.8` anyway. DNS-over-HTTPS is a separate hole this checkbox does not close.
- [ ] **IoT and TVs on guest Wi-Fi or their own VLAN.** A TV on the main LAN can see other devices. Guest isolation is the point. Casting (Google Cast, AirPlay, and similar) uses mDNS, which that isolation drops, so a phone on the main Wi-Fi will not see a TV on the guest network unless you bridge mDNS. Leave the bridge off unless you need casting. The smart-TV steps are in [pihole-tv](../pihole-tv/README.md).
- [ ] **WPS off.** WPS is a second way onto the Wi-Fi, and the PIN is the weak one.

Also worth doing while you are there: WPA2 or WPA3, not WEP or WPA; a long Wi-Fi passphrase; the
admin page bound to the LAN only.

## What the script can check

From a computer on that LAN:

```bash
cd network/router-hygiene
chmod +x check-lan.sh
./check-lan.sh --dry-run    # route and resolver list only; no packets
./check-lan.sh              # ask, then probe
./check-lan.sh --yes
```

After you confirm, it:

- sends one SSDP M-SEARCH (multicast, and to the gateway). An Internet Gateway Device reply means UPnP is answering.
- runs `nmap` against the gateway on a short TCP list (SSH, Telnet, DNS, HTTP, the TR-069 port 7547, and a few common admin ports) **if nmap is installed**. It does not scan the rest of the LAN here.
- shows the resolvers in `/etc/resolv.conf` (and `resolvectl` or `scutil --dns` when those exist).
- sends one DNS query for `example.com` to `8.8.8.8` and to `1.1.1.1`. An answer means this computer can bypass the DNS server DHCP handed out.

No reply is not proof that UPnP is off. A timeout is not proof the router is blocking `8.8.8.8`.
The script says what it saw and stops there. It never logs into the router.
