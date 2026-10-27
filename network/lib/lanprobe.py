#!/usr/bin/env python3
"""LAN checks for privacy-sweep.

The shell scripts decide whether a probe is allowed to leave the machine.
This file parses local tables (ARP, routes, resolv.conf) and, when asked,
sends a short SSDP search, a ping-scan via nmap, and one DNS query to a
public resolver. It only targets the host's own subnet and gateway.

Nothing here logs into a router or changes its settings.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import re
import shutil
import socket
import struct
import subprocess
import sys
from pathlib import Path

TV_NAME = re.compile(
    r"(bravia|roku|vizio|webos|tizen|lgtv|lg-tv|fire-?tv|chromecast|"
    r"apple-?tv|smart-?tv|android-?tv|googletv|smartcast|inscape)",
    re.IGNORECASE,
)
TV_SERVICE = re.compile(
    r"(roku|bravia|webos|tizen|vizio|chromecast|googlecast|androidtv|firetv|smartcast)",
    re.IGNORECASE,
)
PHONE_NAME = re.compile(r"(iphone|ipad|android|galaxy|pixel|phone)", re.IGNORECASE)
TV_VENDOR = re.compile(
    r"(samsung electronics|lg electronics|lg innotek|roku|vizio|funai|"
    r"hisense|tcl\b|sony corporation|onn\b)",
    re.IGNORECASE,
)
NMAP_PORTS = "21,22,23,53,80,443,139,445,1900,5000,5353,7547,8080,8200,8291,8443,8728,49152"


def parse_ip_route(text: str) -> tuple[str, str]:
    """Linux `ip route` / `ip -4 route`. Returns gateway, interface."""
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 5 and parts[0] == "default" and parts[1] == "via":
            gw = parts[2]
            iface = ""
            if "dev" in parts:
                iface = parts[parts.index("dev") + 1]
            return gw, iface
    return "", ""


def parse_macos_route(text: str) -> tuple[str, str]:
    gw, iface = "", ""
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key, value = key.strip().lower(), value.strip()
        if key == "gateway":
            gw = value
        elif key == "interface":
            iface = value
    return gw, iface


def parse_resolv(text: str) -> list[str]:
    servers = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "nameserver":
            servers.append(parts[1])
    return servers


def parse_arp(text: str) -> list[dict]:
    """Accept `ip neigh`, /proc/net/arp, and `arp -an`."""
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("ip address"):
            continue
        if " lladdr " in f" {line} ":
            parts = line.split()
            ip = parts[0]
            mac = parts[parts.index("lladdr") + 1] if "lladdr" in parts else ""
            dev = parts[parts.index("dev") + 1] if "dev" in parts else ""
            state = parts[-1] if parts else ""
            if mac and mac != "00:00:00:00:00:00":
                rows.append({"ip": ip, "mac": _mac(mac), "dev": dev, "state": state})
            continue
        if line.startswith("?") or " at " in line:
            # arp -an: ? (192.0.2.1) at aa:bb:cc:dd:ee:ff on en0 ...
            match = re.search(r"\(([^)]+)\)\s+at\s+(\S+)", line)
            if not match:
                continue
            ip, mac = match.group(1), match.group(2)
            if mac in ("(incomplete)", "<incomplete>"):
                continue
            dev = ""
            on = re.search(r"\bon\s+(\S+)", line)
            if on:
                dev = on.group(1)
            rows.append({"ip": ip, "mac": _mac(mac), "dev": dev, "state": "arp"})
            continue
        # ip neigh with no lladdr (FAILED, INCOMPLETE) has no address to report.
        if " dev " in f" {line} " and " lladdr " not in f" {line} ":
            continue
        parts = line.split()
        if len(parts) >= 4 and re.match(r"\d+\.\d+\.\d+\.\d+$", parts[0]):
            mac = parts[3]
            if mac in ("00:00:00:00:00:00", "0x0"):
                continue
            flags = parts[2] if len(parts) > 2 else ""
            if flags in ("0x0", "0x0000"):
                continue
            dev = parts[5] if len(parts) > 5 else ""
            rows.append({"ip": parts[0], "mac": _mac(mac), "dev": dev, "state": flags})
    return rows


def parse_nmap_hosts(text: str) -> list[dict]:
    """Parse `nmap -sn -oG -` host lines."""
    found = []
    for line in text.splitlines():
        if not line.startswith("Host:"):
            continue
        match = re.search(r"Host:\s+(\S+)\s+\(([^)]*)\)", line)
        if not match:
            continue
        found.append({"ip": match.group(1), "name": match.group(2).strip()})
    return found


def parse_ssdp(payload: str) -> dict:
    headers = {}
    for line in payload.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        headers[key.strip().upper()] = value.strip()
    location = headers.get("LOCATION", "")
    ip = ""
    # LOCATION is http://10.0.0.40:8060/ or http://[fe80::1]:1900/. Keep the address, drop the port.
    match = re.search(r"https?://(\[[0-9a-fA-F:.]+\]|\d{1,3}(?:\.\d{1,3}){3})", location, re.IGNORECASE)
    if match:
        ip = match.group(1).strip("[]")
    return {
        "server": headers.get("SERVER", ""),
        "st": headers.get("ST", ""),
        "usn": headers.get("USN", ""),
        "location": location,
        "ip": ip,
    }


def _mac(value: str) -> str:
    text = value.strip().lower().replace("-", ":")
    return text


def is_private(ip: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return addr.is_private or addr.is_link_local or addr.is_loopback


def classify(name: str, services: str, vendor: str) -> str:
    """Return likely-tv, possible-vendor, or ''.

    A phone-shaped name is not called a TV just because the vendor also
    makes televisions.
    """
    blob_name = name or ""
    if PHONE_NAME.search(blob_name):
        return ""
    if TV_NAME.search(blob_name) or TV_SERVICE.search(services or ""):
        return "likely-tv"
    if vendor and TV_VENDOR.search(vendor):
        return "possible-vendor"
    return ""


def read_local() -> dict:
    """Gateway, interface, and resolver list. No packets are sent."""
    gateway, iface = "", ""
    resolvers: list[str] = []
    notes = []
    if sys.platform.startswith("linux") and shutil.which("ip"):
        route = subprocess.run(["ip", "-4", "route"], capture_output=True, text=True, check=False)
        gateway, iface = parse_ip_route(route.stdout)
    elif sys.platform == "darwin":
        route = subprocess.run(["route", "-n", "get", "default"], capture_output=True, text=True, check=False)
        gateway, iface = parse_macos_route(route.stdout)
    else:
        notes.append("Could not find a route command for this OS.")
    resolv = Path("/etc/resolv.conf")
    if resolv.is_file():
        resolvers = parse_resolv(resolv.read_text(encoding="utf-8", errors="replace"))
    if shutil.which("resolvectl"):
        resolved = subprocess.run(["resolvectl", "dns"], capture_output=True, text=True, check=False)
        extra = re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", resolved.stdout)
        for item in extra:
            if item not in resolvers:
                resolvers.append(item)
        if extra:
            notes.append("resolvectl reported DNS servers; systemd-resolved may be in front of /etc/resolv.conf.")
    if sys.platform == "darwin" and shutil.which("scutil"):
        dns = subprocess.run(["scutil", "--dns"], capture_output=True, text=True, check=False)
        for item in re.findall(r"nameserver\[\d+\]\s*:\s*(\S+)", dns.stdout):
            if item not in resolvers:
                resolvers.append(item)
    return {"gateway": gateway, "iface": iface, "resolvers": resolvers, "notes": notes}


def read_arp() -> list[dict]:
    if shutil.which("ip"):
        result = subprocess.run(["ip", "neigh"], capture_output=True, text=True, check=False)
        rows = parse_arp(result.stdout)
        if rows:
            return rows
    proc = Path("/proc/net/arp")
    if proc.is_file():
        rows = parse_arp(proc.read_text(encoding="utf-8", errors="replace"))
        if rows:
            return rows
    if shutil.which("arp"):
        result = subprocess.run(["arp", "-an"], capture_output=True, text=True, check=False)
        return parse_arp(result.stdout)
    return []


def local_ipv4() -> tuple[str, str]:
    """Return this host's IPv4 and the network in CIDR, if we can see one."""
    if not shutil.which("ip"):
        return "", ""
    result = subprocess.run(["ip", "-4", "-o", "addr", "show"], capture_output=True, text=True, check=False)
    for line in result.stdout.splitlines():
        match = re.search(r"\binet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)\b", line)
        if not match:
            continue
        ip, prefix = match.group(1), int(match.group(2))
        if ip.startswith("127."):
            continue
        network = ipaddress.ip_network(f"{ip}/{prefix}", strict=False)
        return ip, str(network)
    return "", ""


def _ssdp_search(targets: list[tuple[str, int]], timeout: float = 2.5) -> list[dict]:
    message = "\r\n".join(
        [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            'MAN: "ssdp:discover"',
            "MX: 1",
            "ST: ssdp:all",
            "",
            "",
        ]
    ).encode("ascii")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    replies = []
    try:
        sock.settimeout(timeout)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        for host, port in targets:
            try:
                sock.sendto(message, (host, port))
            except OSError as exc:
                replies.append({"error": f"{host}: {exc}", "server": "", "st": "", "location": "", "ip": "", "usn": ""})
        deadline = time_now() + timeout
        while True:
            remain = deadline - time_now()
            if remain <= 0:
                break
            sock.settimeout(remain)
            try:
                data, addr = sock.recvfrom(8192)
            except socket.timeout:
                break
            except OSError:
                break
            parsed = parse_ssdp(data.decode("utf-8", "replace"))
            parsed["from"] = addr[0]
            if not parsed["ip"]:
                parsed["ip"] = addr[0]
            replies.append(parsed)
    finally:
        sock.close()
    return replies


def time_now() -> float:
    import time

    return time.monotonic()


def dns_query(name: str, server: str, timeout: float = 3.0) -> str:
    """Send one A query. Return 'answer', 'refused', 'no-answer', or 'timeout'."""
    packet = _dns_query_packet(name)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.settimeout(timeout)
        sock.sendto(packet, (server, 53))
        data, _addr = sock.recvfrom(1500)
    except socket.timeout:
        return "timeout"
    except OSError as exc:
        return f"error: {exc}"
    finally:
        sock.close()
    if len(data) < 12:
        return "no-answer"
    _id, flags, qd, an, _ns, _ar = struct.unpack("!HHHHHH", data[:12])
    rcode = flags & 0x0F
    if an > 0:
        return "answer"
    if rcode == 5:
        return "refused"
    if qd or rcode == 0:
        return "no-answer"
    return f"rcode-{rcode}"


def _dns_query_packet(name: str) -> bytes:
    header = struct.pack("!HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0)
    question = _encode_name(name) + struct.pack("!HH", 1, 1)
    return header + question


def _encode_name(name: str) -> bytes:
    out = b""
    for label in name.rstrip(".").split("."):
        raw = label.encode("ascii")
        if len(raw) > 63:
            raise ValueError("label too long")
        out += bytes([len(raw)]) + raw
    return out + b"\x00"


def _decode_name(packet: bytes, offset: int, depth: int = 0) -> tuple[str, int]:
    if depth > 8:
        raise ValueError("name compression too deep")
    labels = []
    jumped = False
    end = offset
    while offset < len(packet):
        length = packet[offset]
        if length == 0:
            offset += 1
            if not jumped:
                end = offset
            break
        if length & 0xC0 == 0xC0:
            if offset + 1 >= len(packet):
                break
            pointer = ((length & 0x3F) << 8) | packet[offset + 1]
            target, _ignored = _decode_name(packet, pointer, depth + 1)
            labels.append(target)
            offset += 2
            if not jumped:
                end = offset
            jumped = True
            break
        offset += 1
        labels.append(packet[offset : offset + length].decode("ascii", "replace"))
        offset += length
        if not jumped:
            end = offset
    return ".".join(labels), end


def parse_mdns_names(packet: bytes) -> list[str]:
    """Pull DNS names out of an mDNS response. Bad packets yield []."""
    try:
        if len(packet) < 12:
            return []
        _id, _flags, qd, an, ns, ar = struct.unpack("!HHHHHH", packet[:12])
        offset = 12
        names = []
        for _ in range(qd + an + ns + ar):
            if offset >= len(packet):
                break
            name, offset = _decode_name(packet, offset)
            if name:
                names.append(name)
            if offset + 4 > len(packet):
                break
            _typ, _clas = struct.unpack("!HH", packet[offset : offset + 4])
            offset += 4
            # Questions end here. Records have TTL and RDATA.
            if _ > qd - 1 or qd == 0:
                # After the question section, records include ttl + rdlength.
                # The counter above already consumed questions. Detect by
                # remaining counts: we don't know which section we're in
                # cleanly once mixed. Peek: if 6 more bytes exist, treat as RR
                # only when this index is past the questions.
                pass
        # Second pass that understands records, questions skipped properly.
        return _mdns_names_pass(packet)
    except (struct.error, ValueError, IndexError):
        return []


def _mdns_names_pass(packet: bytes) -> list[str]:
    _id, _flags, qd, an, ns, ar = struct.unpack("!HHHHHH", packet[:12])
    offset = 12
    names: list[str] = []
    for index in range(qd):
        _name, offset = _decode_name(packet, offset)
        offset += 4
    for _index in range(an + ns + ar):
        name, offset = _decode_name(packet, offset)
        if name:
            names.append(name)
        if offset + 10 > len(packet):
            break
        rtype, _clas, _ttl, rdlength = struct.unpack("!HHIH", packet[offset : offset + 10])
        offset += 10
        rdata = packet[offset : offset + rdlength]
        offset += rdlength
        if rtype in (12, 33):  # PTR, SRV
            try:
                target, _end = _decode_name(packet, offset - rdlength)
                if target:
                    names.append(target)
            except (ValueError, IndexError, struct.error):
                continue
        elif rtype == 1 and len(rdata) == 4:
            names.append(".".join(str(b) for b in rdata))
    return names


def mdns_browse(timeout: float = 2.0) -> list[dict]:
    """Ask for a few common service types. Each item has ip, name, service."""
    if shutil.which("avahi-browse"):
        result = subprocess.run(
            ["avahi-browse", "-artp", "-t"],
            capture_output=True,
            text=True,
            timeout=timeout + 3,
            check=False,
        )
        records = []
        for line in result.stdout.splitlines():
            if not line.startswith("="):
                continue
            parts = line.split(";")
            # =;iface;proto;name;type;domain;host;address;port;txt
            if len(parts) >= 8:
                records.append({"ip": parts[7], "name": parts[3] or parts[6], "service": parts[4]})
        return records
    services = [
        "_googlecast._tcp.local",
        "_androidtvremote2._tcp.local",
        "_airplay._tcp.local",
        "_roku._tcp.local",
        "_hap._tcp.local",
        "_http._tcp.local",
        "_device-info._tcp.local",
        "_workstation._tcp.local",
    ]
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    names: list[str] = []
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(timeout)
        for service in services:
            query = struct.pack("!HHHHHH", 0, 0, 1, 0, 0, 0) + _encode_name(service) + struct.pack("!HH", 12, 1)
            try:
                sock.sendto(query, ("224.0.0.251", 5353))
            except OSError:
                return names
        deadline = time_now() + timeout
        while time_now() < deadline:
            sock.settimeout(max(0.1, deadline - time_now()))
            try:
                data, _addr = sock.recvfrom(9000)
            except socket.timeout:
                break
            except OSError:
                break
            names.extend(parse_mdns_names(data))
    finally:
        sock.close()
    return [{"ip": "", "name": name, "service": name} for name in names if name]


def nmap_ping(cidr: str) -> tuple[list[dict], str]:
    if not shutil.which("nmap"):
        return [], "nmap is not installed, so the ping scan was skipped."
    network = ipaddress.ip_network(cidr, strict=False)
    if network.prefixlen < 22:
        return [], f"Refusing to ping-scan {cidr}: the prefix is wider than /22."
    result = subprocess.run(
        ["nmap", "-sn", "-n", "-oG", "-", "--max-retries", "1", "--host-timeout", "2s", cidr],
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    if result.returncode not in (0, 1):
        return [], f"nmap exited {result.returncode}."
    return parse_nmap_hosts(result.stdout), ""


def nmap_gateway(gateway: str) -> tuple[str, str]:
    if not gateway or not is_private(gateway):
        return "", "No private gateway address, so ports were not scanned."
    if not shutil.which("nmap"):
        return "", "nmap is not installed, so the gateway port check was skipped."
    result = subprocess.run(
        ["nmap", "-Pn", "-sT", "-n", "-p", NMAP_PORTS, "--open", "-T4", gateway],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    interesting = []
    for line in result.stdout.splitlines():
        if "/tcp" in line and "open" in line:
            interesting.append(line.strip())
    if not interesting:
        return "(no open ports in the short list)", ""
    return "\n".join(interesting), ""


def load_name_map(path: str) -> dict[str, dict]:
    if not path:
        return {}
    file = Path(path)
    if not file.is_file():
        return {}
    payload = json.loads(file.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        return {}
    return payload


def merge_inventory(arp_rows: list[dict], mdns_names: list[dict], ssdp: list[dict], nmap_hosts: list[dict], pihole: dict, gateway: str, me: str) -> list[dict]:
    hosts: dict[str, dict] = {}

    def slot(ip: str) -> dict:
        if ip not in hosts:
            hosts[ip] = {
                "ip": ip,
                "mac": "",
                "names": [],
                "services": [],
                "vendor": "",
                "sources": [],
            }
        return hosts[ip]

    def add_name(row: dict, name: str) -> None:
        name = (name or "").strip()
        if name and name not in row["names"] and name != row["ip"]:
            row["names"].append(name)

    for item in arp_rows:
        row = slot(item["ip"])
        row["mac"] = item.get("mac") or row["mac"]
        if "arp" not in row["sources"]:
            row["sources"].append("arp")
    for item in nmap_hosts:
        row = slot(item["ip"])
        add_name(row, item.get("name") or "")
        if "nmap" not in row["sources"]:
            row["sources"].append("nmap")
    loose_mdns: list[dict] = []
    for item in mdns_names:
        ip = str(item.get("ip") or "")
        if re.match(r"(\d+\.){3}\d+$", ip):
            row = slot(ip)
            add_name(row, str(item.get("name") or ""))
            if item.get("service"):
                row["services"].append(str(item["service"]))
            if "mdns" not in row["sources"]:
                row["sources"].append("mdns")
        else:
            loose_mdns.append(item)
    for item in ssdp:
        ip = item.get("ip") or item.get("from") or ""
        if not ip:
            continue
        row = slot(ip)
        add_name(row, item.get("server") or "")
        if item.get("st"):
            row["services"].append(item["st"])
        if "ssdp" not in row["sources"]:
            row["sources"].append("ssdp")
    for ip, info in pihole.items():
        if not isinstance(info, dict):
            continue
        row = slot(ip)
        add_name(row, str(info.get("name") or ""))
        if info.get("mac") and not row["mac"]:
            row["mac"] = _mac(str(info["mac"]))
        if info.get("vendor"):
            row["vendor"] = str(info["vendor"])
        if "pihole" not in row["sources"]:
            row["sources"].append("pihole")
    results = []
    for ip, row in hosts.items():
        if not ip or ip == me:
            continue
        service_text = " ".join(row["services"])
        name_text = " ".join(row["names"])
        for item in loose_mdns:
            blob = str(item.get("name") or "") + " " + str(item.get("service") or "")
            if name_text and any(part and part in blob for part in name_text.split()):
                service_text = (service_text + " " + blob).strip()
        flag = classify(name_text, service_text, row["vendor"])
        unknown = not row["names"] and not row["vendor"] and ip != gateway
        results.append(
            {
                "ip": ip,
                "mac": row["mac"],
                "names": row["names"],
                "vendor": row["vendor"],
                "sources": row["sources"],
                "flag": flag,
                "unknown": unknown,
                "gateway": ip == gateway,
            }
        )
    def _ip_key(item: dict) -> tuple:
        try:
            return tuple(int(part) for part in item["ip"].split("."))
        except ValueError:
            return (999,)

    results.sort(key=_ip_key)
    return results


def format_inventory(rows: list[dict], meta: dict) -> str:
    lines = ["== LAN inventory ==", f"This host: {meta.get('me') or 'unknown'}", f"Gateway: {meta.get('gateway') or 'unknown'}"]
    if meta.get("cidr"):
        lines.append(f"Subnet considered: {meta['cidr']}")
    if meta.get("note"):
        lines.append(meta["note"])
    lines.append("Sources: " + ", ".join(meta.get("sources") or ["arp"]))
    lines.append("")
    tvs = [row for row in rows if row["flag"] == "likely-tv"]
    lines.append(f"TVs on this LAN: {len(tvs)}")
    if not tvs:
        lines.append("  None matched the TV name/service checks. A TV on guest Wi-Fi is invisible from here.")
    for row in tvs:
        lines.append(f"  {row['ip']}  {row['mac'] or '-'}  {', '.join(row['names']) or '(no name)'}")
    lines.append("")
    unknown = [row for row in rows if row["unknown"]]
    lines.append(f"Unknown devices (address only, no name from mDNS, SSDP, or Pi-hole): {len(unknown)}")
    for row in unknown:
        lines.append(f"  {row['ip']}  {row['mac'] or '-'}")
    lines.append("")
    lines.append("All neighbors:")
    for row in rows:
        flags = []
        if row["gateway"]:
            flags.append("gateway")
        if row["flag"]:
            flags.append(row["flag"])
        if row["unknown"]:
            flags.append("unknown")
        mark = ("  [" + ", ".join(flags) + "]") if flags else ""
        names = ", ".join(row["names"]) if row["names"] else "-"
        lines.append(f"  {row['ip']:<16} {row['mac'] or '-':<18} {names}{mark}")
    lines.append("")
    lines.append("Run this while joined to the main LAN. A guest VLAN this computer is not on will not appear.")
    lines.append("'possible-vendor' means the Pi-hole vendor string looks like a TV maker. Phones from those makers are not flagged when the name looks like a phone.")
    return "\n".join(lines) + "\n"


def format_hygiene(local: dict, active: dict | None) -> str:
    lines = ["== Router hygiene checks (from this host) =="]
    lines.append(f"Gateway: {local['gateway'] or '(none found)'}")
    if local["iface"]:
        lines.append(f"Interface: {local['iface']}")
    if local["resolvers"]:
        lines.append("DNS resolvers this host is using:")
        for item in local["resolvers"]:
            lines.append(f"  {item}")
    else:
        lines.append("No DNS resolvers found in resolv.conf.")
    for note in local["notes"]:
        lines.append(note)
    lines.append("")
    lines.append("These checks do not log into the router.")
    lines.append("They cannot see the admin password, the firmware version, WPS, or a guest SSID.")
    if active is None:
        lines.append("")
        lines.append("Probes used only after you confirm or pass --yes:")
        lines.append("  one SSDP M-SEARCH on the LAN and to the gateway")
        lines.append(f"  nmap against the gateway on ports {NMAP_PORTS}, if nmap is installed")
        lines.append("  one DNS A query for example.com to 8.8.8.8 and to 1.1.1.1")
        return "\n".join(lines) + "\n"
    lines.append("")
    lines.append("SSDP / UPnP replies:")
    replies = active.get("ssdp") or []
    if not replies:
        lines.append("  No SSDP reply. UPnP may be off, or the router does not answer multicast.")
    igd = False
    for item in replies:
        if item.get("error"):
            lines.append(f"  {item['error']}")
            continue
        blob = " ".join([item.get("server", ""), item.get("st", ""), item.get("usn", "")])
        if re.search(r"InternetGatewayDevice|WANIPConnection|WANPPPConnection", blob, re.I):
            igd = True
        lines.append(f"  from {item.get('from') or item.get('ip') or '?'}: {item.get('server') or item.get('st') or 'reply'}")
    if igd:
        lines.append("  An Internet Gateway Device answered. UPnP is likely enabled.")
    elif replies:
        lines.append("  Replies arrived, but none identified itself as an Internet Gateway Device.")
    lines.append("")
    lines.append("Gateway ports (short list, TCP connect):")
    lines.append(active.get("ports") or "  (not run)")
    if active.get("ports_note"):
        lines.append(active["ports_note"])
    lines.append("")
    lines.append("Direct DNS to a public resolver (does this LAN allow bypassing Pi-hole?):")
    for server, result in active.get("dns") or []:
        if result == "answer":
            lines.append(f"  {server}: got an answer. This host can resolve without using the configured DNS.")
        elif result == "timeout":
            lines.append(f"  {server}: no answer before the timeout. The path may be blocked, or it is just filtered.")
        else:
            lines.append(f"  {server}: {result}")
    lines.append("A successful answer means a device that ignores DHCP DNS can still reach that resolver.")
    return "\n".join(lines) + "\n"


def cmd_passive(_args: argparse.Namespace) -> int:
    sys.stdout.write(format_hygiene(read_local(), None))
    return 0


def cmd_active(_args: argparse.Namespace) -> int:
    local = read_local()
    targets = [("239.255.255.250", 1900)]
    if local["gateway"] and is_private(local["gateway"]):
        targets.append((local["gateway"], 1900))
    ssdp = _ssdp_search(targets)
    ports, note = nmap_gateway(local["gateway"])
    dns = [(server, dns_query("example.com", server)) for server in ("8.8.8.8", "1.1.1.1")]
    active = {"ssdp": ssdp, "ports": ports, "ports_note": note, "dns": dns}
    sys.stdout.write(format_hygiene(local, active))
    return 0


def cmd_inventory(args: argparse.Namespace) -> int:
    local = read_local()
    me, cidr = local_ipv4()
    arp_rows = read_arp()
    mdns: list[str] = []
    ssdp: list[dict] = []
    nmap_hosts: list[dict] = []
    sources = ["arp"]
    note = ""
    if args.active:
        mdns = mdns_browse()
        sources.append("mdns")
        targets = [("239.255.255.250", 1900)]
        if local["gateway"]:
            targets.append((local["gateway"], 1900))
        ssdp = _ssdp_search(targets)
        sources.append("ssdp")
        if cidr:
            nmap_hosts, note = nmap_ping(cidr)
            if nmap_hosts or not note:
                sources.append("nmap")
        else:
            note = "Could not determine an IPv4 subnet, so nmap -sn was not run."
    pihole = load_name_map(args.names)
    if pihole:
        sources.append("pihole")
    rows = merge_inventory(arp_rows, mdns, ssdp, nmap_hosts, pihole, local["gateway"], me)
    meta = {"me": me, "gateway": local["gateway"], "cidr": cidr, "sources": sources, "note": note}
    sys.stdout.write(format_inventory(rows, meta))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="LAN probes for privacy-sweep. Prefer the shell scripts.")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("passive")
    sub.add_parser("active")
    inv = sub.add_parser("inventory")
    inv.add_argument("--active", action="store_true")
    inv.add_argument("--names", default="", help="JSON file of ip -> {name, mac, vendor} from Pi-hole.")
    args = parser.parse_args(argv)
    if args.cmd == "passive":
        return cmd_passive(args)
    if args.cmd == "active":
        return cmd_active(args)
    return cmd_inventory(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
