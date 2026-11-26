#!/usr/bin/env python3
import json
import sys
from pathlib import Path

import yaml

TOPOLOGY = Path(__file__).resolve().parent.parent.parent / "topology.yml"
OS_GROUP = {"debian": "linux", "windows": "windows", "opnsense": "firewall"}


def group_name(tag):
    return tag.replace("-", "_")      


def build():
    topo = yaml.safe_load(TOPOLOGY.read_text())
    entries = topo.get("hosts", []) + topo.get("other", [])
    inv = {"_meta": {"hostvars": {}}}

    for h in entries:
        ip = h["ip"]
        if ip == "dhcp":
            ip = h.get("reserved_ip")
            if not ip:
                print(f"пропущен {h['name']}: для DHCP-хоста не задан reserved_ip", file=sys.stderr)
                continue

        name = h["name"]
        inv["_meta"]["hostvars"][name] = {
            "ansible_host": ip.split("/")[0],     
            "vmid": h["vmid"],
            "vlan": h.get("vlan"),
        }
        groups = [OS_GROUP.get(h.get("os", "debian"), "ungrouped")]
        groups += [group_name(t) for t in h.get("tags", [])]
        for g in groups:
            inv.setdefault(g, {"hosts": []})["hosts"].append(name)
    return inv


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--host":
        print("{}")                        
    else:
        print(json.dumps(build(), indent=2))
