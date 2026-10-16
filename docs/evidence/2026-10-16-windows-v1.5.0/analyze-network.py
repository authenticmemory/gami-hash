"""Correlate Sysmon GAMI Hash descendants with NIC packet endpoints."""

import json
import re
import zipfile
from collections import Counter
from pathlib import Path
from io import TextIOWrapper

root = Path(__file__).resolve().parent
events = json.loads((root / "sysmon-events.json").read_text(encoding="utf-8-sig"))
creates = [event for event in events if event["EventId"] == 1]
apps = [event for event in creates if event["Image"].lower().endswith(r"\gami hash.exe")]
if len(apps) != 1:
    raise SystemExit(f"Expected one GAMI Hash GUI process, got {len(apps)}")
app = apps[0]
descendants = {app["ProcessGuid"]}
while True:
    children = {
        event["ProcessGuid"]
        for event in creates
        if event["ParentProcessGuid"] in descendants
    }
    expanded = descendants | children
    if expanded == descendants:
        break
    descendants = expanded

webviews = [
    event
    for event in creates
    if event["ProcessGuid"] in descendants
    and event["Image"].lower().endswith(r"\msedgewebview2.exe")
]
activity = [
    event
    for event in events
    if event["EventId"] in (3, 22) and event["ProcessGuid"] in descendants
]
(root / "app-sysmon-events.json").write_text(
    json.dumps(
        [event for event in events if event["ProcessGuid"] in descendants and event["EventId"] in (1, 3, 22)],
        indent=2,
    ) + "\n",
    encoding="utf-8",
)
dns = [event for event in activity if event["EventId"] == 22]
connections = [event for event in activity if event["EventId"] == 3]
external = [
    event
    for event in connections
    if event["DestinationPort"] == "443"
    and event["DestinationIp"] not in ("192.168.247.2", "192.168.247.128")
    and event["Initiated"] == "true"
]
flows = {}
for event in external:
    key = (event["SourceIp"], event["SourcePort"], event["DestinationIp"], event["DestinationPort"])
    if key not in flows:
        flows[key] = {
            "first_sysmon_utc": event["TimeUTC"],
            "process_id": event["ProcessId"],
            "process_guid": event["ProcessGuid"],
            "source_ip": event["SourceIp"],
            "source_port": event["SourcePort"],
            "destination_ip": event["DestinationIp"],
            "destination_port": event["DestinationPort"],
            "sysmon_events": 0,
            "packets_out": 0,
            "packets_in": 0,
        }
    flows[key]["sysmon_events"] += 1

packet = re.compile(
    r"\b(?P<src>\d+\.\d+\.\d+\.\d+)\.(?P<srcport>\d+) > "
    r"(?P<dst>\d+\.\d+\.\d+\.\d+)\.(?P<dstport>\d+): tcp"
)
with zipfile.ZipFile(root / "gami-network-text.zip") as archive:
    with TextIOWrapper(archive.open("gami-network.txt"), encoding="utf-16", errors="replace") as lines:
        for line in lines:
            match = packet.search(line)
            if not match:
                continue
            data = match.groupdict()
            outgoing = (data["src"], data["srcport"], data["dst"], data["dstport"])
            incoming = (data["dst"], data["dstport"], data["src"], data["srcport"])
            if outgoing in flows:
                flows[outgoing]["packets_out"] += 1
            if incoming in flows:
                flows[incoming]["packets_in"] += 1

summary = {
    "app": {"pid": app["ProcessId"], "guid": app["ProcessGuid"], "created_utc": app["TimeUTC"]},
    "webview_child_count": len(webviews),
    "webview_children": [
        {"pid": event["ProcessId"], "parent_pid": event["ParentProcessId"], "guid": event["ProcessGuid"]}
        for event in webviews
    ],
    "dns_queries": [
        {"utc": event["TimeUTC"], "pid": event["ProcessId"], "name": event["QueryName"], "status": event["QueryStatus"]}
        for event in sorted(dns, key=lambda item: item["TimeUTC"])
    ],
    "external_destinations": dict(Counter(event["DestinationIp"] for event in external)),
    "flows": sorted(flows.values(), key=lambda item: item["first_sysmon_utc"]),
}
(root / "network-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(f"WebView children: {len(webviews)}; external flows: {len(flows)}")
for flow in summary["flows"]:
    print(
        f'{flow["first_sysmon_utc"]} PID {flow["process_id"]} '
        f'{flow["source_port"]} -> {flow["destination_ip"]}:{flow["destination_port"]} '
        f'packets out/in {flow["packets_out"]}/{flow["packets_in"]}'
    )
