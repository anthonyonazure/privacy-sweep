#!/usr/bin/env python3
"""Unit tests for the Pi-hole and LAN helpers. No network."""

from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "network" / "lib"))

import lanprobe  # noqa: E402
import pihole  # noqa: E402

FIXTURE = ROOT / "tests" / "fixtures" / "pihole"


class ReportTests(unittest.TestCase):
    def test_fixture_window_excludes_old_acr_hit(self) -> None:
        spec = json.loads((FIXTURE / "queries.json").read_text(encoding="utf-8"))
        con = pihole._build_v6_memory(spec)
        suffixes = pihole.load_suffixes(ROOT / "network" / "pihole-tv" / "acr-suffixes.txt")
        now = int(spec["now"])
        report = pihole._report_from_db(con, now - 7 * 86400, now, suffixes, 10)
        self.assertEqual(report.total, 4)
        self.assertEqual(report.blocked, 2)
        domains = {row["domain"] for row in report.acr}
        self.assertIn("log-1.samsungacr.com", domains)
        self.assertIn("scribe.logs.roku.com", domains)
        self.assertNotIn("old.samsungacr.com", domains)
        names = {row["ip"]: row["name"] for row in report.acr}
        self.assertEqual(names["10.0.0.40"], "living-room-tv")
        blocked_names = {row["domain"] for row in report.blocked_domains}
        self.assertIn("ads.example", blocked_names)
        self.assertIn("log-1.samsungacr.com", blocked_names)

    def test_v5_schema_still_answers(self) -> None:
        con = sqlite3.connect(":memory:")
        con.row_factory = sqlite3.Row
        con.execute(
            "CREATE TABLE queries (id INTEGER, timestamp INTEGER, status INTEGER, domain TEXT, client TEXT)"
        )
        con.execute(
            "INSERT INTO queries VALUES (1, 100, 1, 'log-1.samsungacr.com', '10.1.1.8')"
        )
        con.commit()
        suffixes = [("samsungacr.com", "samsung-acr")]
        report = pihole._report_from_db(con, 0, 200, suffixes, 5)
        self.assertEqual(report.acr[0]["ip"], "10.1.1.8")
        self.assertEqual(report.acr[0]["blocked"], 1)

    def test_plan_skips_urls_already_present(self) -> None:
        catalog = pihole.load_lists(ROOT / "network" / "pihole-tv" / "lists.txt", include_vendor=False)
        existing = json.loads((FIXTURE / "lists.json").read_text(encoding="utf-8"))["lists"]
        plan = pihole.plan_lists(catalog, existing)
        present = {row["url"] for row in plan["present"]}
        added = {row["url"] for row in plan["add"]}
        self.assertIn("https://raw.githubusercontent.com/blocklistproject/Lists/master/smart-tv.txt", present)
        self.assertIn("https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt", added)
        self.assertEqual(len(catalog), 2)

    def test_vendor_lists_are_opt_in(self) -> None:
        plain = pihole.load_lists(ROOT / "network" / "pihole-tv" / "lists.txt", include_vendor=False)
        wider = pihole.load_lists(ROOT / "network" / "pihole-tv" / "lists.txt", include_vendor=True)
        self.assertEqual(len(plain), 2)
        self.assertEqual(len(wider), 5)
        self.assertTrue(all(row["url"].startswith("https://") for row in wider))

    def test_gravity_insert_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "gravity.db"
            con = sqlite3.connect(db)
            con.execute(
                "CREATE TABLE adlist (id INTEGER PRIMARY KEY, address TEXT UNIQUE, enabled INTEGER, comment TEXT, date_added INTEGER, date_modified INTEGER)"
            )
            con.execute(
                "CREATE TABLE domainlist (id INTEGER PRIMARY KEY, type INTEGER, domain TEXT, enabled INTEGER, comment TEXT)"
            )
            con.commit()
            con.close()
            catalog = pihole.load_lists(ROOT / "network" / "pihole-tv" / "lists.txt", False)
            plan = pihole.plan_lists(catalog, [])
            pihole.apply_gravity_file(db, plan, True, False)
            pihole.apply_gravity_file(db, plan, True, False)
            con = sqlite3.connect(db)
            self.assertEqual(con.execute("SELECT COUNT(*) FROM adlist").fetchone()[0], len(plan["add"]))
            self.assertEqual(con.execute("SELECT COUNT(*) FROM domainlist WHERE type = 3").fetchone()[0], 1)
            con.close()

    def test_new_clients_and_baseline(self) -> None:
        clients = [("10.0.0.10", "laptop"), ("10.0.0.40", "tv")]
        self.assertEqual(pihole.diff_clients(set(), clients), clients)
        self.assertEqual(pihole.diff_clients({"10.0.0.10"}, clients), [("10.0.0.40", "tv")])

    def test_network_device_parser(self) -> None:
        payload = json.loads((FIXTURE / "devices.json").read_text(encoding="utf-8"))
        parsed = pihole.parse_network_devices(payload)
        self.assertEqual(parsed["10.0.0.40"]["name"], "living-room-tv")
        self.assertIn("Samsung", parsed["10.0.0.40"]["vendor"])


class LanTests(unittest.TestCase):
    def test_arp_formats(self) -> None:
        linux = "10.0.0.1 dev eth0 lladdr aa:bb:cc:dd:ee:01 REACHABLE\n10.0.0.2 dev eth0 FAILED\n"
        rows = lanprobe.parse_arp(linux)
        self.assertEqual(rows, [{"ip": "10.0.0.1", "mac": "aa:bb:cc:dd:ee:01", "dev": "eth0", "state": "REACHABLE"}])
        proc = (
            "IP address       HW type     Flags       HW address            Mask     Device\n"
            "10.0.0.9         0x1         0x2         aa:bb:cc:dd:ee:09     *        eth0\n"
            "10.0.0.8         0x1         0x0         00:00:00:00:00:00     *        eth0\n"
        )
        self.assertEqual(lanprobe.parse_arp(proc)[0]["ip"], "10.0.0.9")
        mac = "? (10.0.0.7) at aa:bb:cc:dd:ee:07 on en0 ifscope [ethernet]\n? (10.0.0.6) at (incomplete) on en0\n"
        parsed = lanprobe.parse_arp(mac)
        self.assertEqual(len(parsed), 1)
        self.assertEqual(parsed[0]["dev"], "en0")

    def test_route_resolv_ssdp_and_tv_flag(self) -> None:
        gw, iface = lanprobe.parse_ip_route("default via 192.168.1.1 dev wlan0 proto dhcp")
        self.assertEqual((gw, iface), ("192.168.1.1", "wlan0"))
        self.assertEqual(lanprobe.parse_resolv("nameserver 127.0.0.53\n# comment\nnameserver 1.1.1.1\n"), ["127.0.0.53", "1.1.1.1"])
        ssdp = lanprobe.parse_ssdp(
            "HTTP/1.1 200 OK\r\nST: roku:ecp\r\nSERVER: Roku/14.0 UPnP/1.0\r\nLOCATION: http://10.0.0.40:8060/\r\n"
        )
        self.assertEqual(ssdp["ip"], "10.0.0.40")
        self.assertEqual(lanprobe.classify("Living Room Roku", ssdp["server"], ""), "likely-tv")
        self.assertEqual(lanprobe.classify("Pixel-7", "", "Samsung Electronics"), "")
        self.assertEqual(lanprobe.classify("office-pc", "", "Samsung Electronics"), "possible-vendor")
        self.assertTrue(lanprobe.is_private("192.168.1.1"))
        self.assertFalse(lanprobe.is_private("8.8.8.8"))

    def test_inventory_flags_tv_and_unknown(self) -> None:
        arp = [{"ip": "10.0.0.40", "mac": "aa:bb:cc:dd:ee:40", "dev": "eth0", "state": "REACHABLE"},
               {"ip": "10.0.0.50", "mac": "aa:bb:cc:dd:ee:50", "dev": "eth0", "state": "REACHABLE"},
               {"ip": "10.0.0.1", "mac": "aa:bb:cc:dd:ee:01", "dev": "eth0", "state": "REACHABLE"}]
        mdns = [{"ip": "10.0.0.40", "name": "Living-Room-Roku", "service": "_googlecast._tcp"}]
        ssdp = [{"ip": "10.0.0.40", "server": "Roku/14", "st": "roku:ecp", "from": "10.0.0.40"}]
        rows = lanprobe.merge_inventory(arp, mdns, ssdp, [], {}, "10.0.0.1", "10.0.0.2")
        by_ip = {row["ip"]: row for row in rows}
        self.assertEqual(by_ip["10.0.0.40"]["flag"], "likely-tv")
        self.assertTrue(by_ip["10.0.0.50"]["unknown"])
        self.assertTrue(by_ip["10.0.0.1"]["gateway"])
        self.assertFalse(by_ip["10.0.0.1"]["unknown"])

    def test_nmap_grepable(self) -> None:
        text = "Host: 10.0.0.5 (tv.local) Status: Up\nHost: 10.0.0.5 () Status: Up\n"
        hosts = lanprobe.parse_nmap_hosts(text)
        self.assertEqual(hosts[0]["name"], "tv.local")

    def test_dns_packet_roundtrip_name(self) -> None:
        packet = lanprobe._dns_query_packet("example.com")
        self.assertGreater(len(packet), 12)
        name, _offset = lanprobe._decode_name(packet, 12)
        self.assertEqual(name, "example.com")


if __name__ == "__main__":
    unittest.main()
