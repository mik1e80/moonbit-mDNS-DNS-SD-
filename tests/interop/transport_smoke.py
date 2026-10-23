"""Short, independent publisher/witness for M0. No production discovery logic."""
import argparse
import hashlib
import importlib.metadata
import json
import platform
import socket
import subprocess
import threading
import time
import uuid
from pathlib import Path

from zeroconf import IPVersion, ServiceInfo, Zeroconf

QUESTION = bytes.fromhex("000000000001000000000000055f68747470045f746370056c6f63616c00000c0001")
ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--interface", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    token = "moondiscover-" + uuid.uuid4().hex[:12]
    info = ServiceInfo(
        "_http._tcp.local.", token + "._http._tcp.local.",
        addresses=[socket.inet_aton(args.interface)], port=43219,
        properties={b"demo": token.encode(), b"binary": b"\x00\xff", b"empty": b""},
        server=token + ".local.",
    )
    witness = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    witness.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    witness.bind(("", 5353))
    witness.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                       socket.inet_aton("224.0.0.251") + socket.inet_aton(args.interface))
    witness.settimeout(0.2)
    observed = []
    stop = threading.Event()

    def listen():
        while not stop.is_set():
            try:
                data, source = witness.recvfrom(65535)
                if data == QUESTION:
                    observed.append({"source": list(source), "sha256": hashlib.sha256(data).hexdigest()})
            except TimeoutError:
                pass

    worker = threading.Thread(target=listen)
    worker.start()
    zc = None
    registered = False
    try:
        zc = Zeroconf(interfaces=[args.interface], ip_version=IPVersion.V4Only)
        zc.register_service(info)
        registered = True
        probes = {}
        for mode in ("multicast", "ordinary"):
            command = [str(ROOT / "_build/native/debug/build/cmd/transport_spike/transport_spike.exe"), args.interface, mode]
            result = subprocess.run(command, capture_output=True, text=True, timeout=8)
            probes[mode] = {"exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
        command = [str(ROOT / "_build/native/debug/build/cmd/native_spike/native_spike.exe"), args.interface]
        result = subprocess.run(command, capture_output=True, text=True, timeout=8)
        events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
        # Publish only our synthetic service packets, excluding unrelated LAN traffic.
        own_packets = [e for e in events if e.get("event") == "packet" and token.encode() in bytes.fromhex(e["hex"])]
        for event in own_packets:
            event["sha256"] = hashlib.sha256(bytes.fromhex(event["hex"])).hexdigest()
        zc.unregister_service(info)
        registered = False
        zc.close()
        zc = None
        stop.set()
        worker.join(timeout=2)
        witness.close()
        # Remove only our test listeners. System/browser 5353 listeners may
        # remain; record unicast delivery as observed, without stopping them.
        marker = b"MD\x84\x00" + b"\x00" * 8
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sender.bind((args.interface, 0))
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            for _ in range(3):
                time.sleep(0.3)
                sender.sendto(marker, (args.interface, 5353))
            unicast_out, unicast_err = process.communicate(timeout=8)
        finally:
            sender.close()
            if process.poll() is None:
                process.kill()
                process.wait()
        unicast_events = [json.loads(line) for line in unicast_out.splitlines() if line.startswith("{")]
        unicast_packets = [e for e in unicast_events if e.get("event") == "packet" and e.get("hex") == marker.hex()]
        report = {
            "stage": "M0 transport spike", "date": "2026-10-23",
            "platform": platform.platform(), "python": platform.python_version(),
            "zeroconf": importlib.metadata.version("zeroconf"),
            "interface_ipv4": args.interface, "token": token,
            "publisher": {"type": info.type, "name": info.name, "port": info.port, "server": info.server},
            "command": "native_spike <interface-ipv4>", "exit_code": result.returncode,
            "stderr": result.stderr, "async_probes": probes,
            "query_witness": observed, "service_packets": own_packets,
            "unicast": {"exit_code": process.returncode, "stderr": unicast_err, "packets": unicast_packets},
            "lifecycle": [e for e in events if e.get("event") in ("bound", "closed")],
            "checks": {
                "native_exit_zero": result.returncode == 0,
                "query_seen_from_selected_ip_and_5353": any(e["source"] == [args.interface, 5353] for e in observed),
                "independent_publisher_response_received": bool(own_packets),
                "independent_response_decoded": bool(own_packets) and all(e.get("decoded_records", -1) > 0 for e in own_packets),
                "ingress_interface_and_multicast_destination": bool(own_packets) and all(e["interface_index"] > 0 and e["destination"] == "224.0.0.251:5353" for e in own_packets),
                "coexistence_and_rebind": any(e.get("second_bind") for e in events) and any(e.get("rebind") for e in events),
                "unicast_received_with_destination_metadata": process.returncode == 0 and any(e.get("destination") == args.interface + ":5353" and e.get("interface_index", 0) > 0 for e in unicast_packets),
            },
            "limits": ["same-host Windows experiment; no second-device or Linux validation", "no production cache or DNS-SD aggregation yet", "IP receive TTL not exposed", "only test publisher/witness listeners were closed for unicast; system/browser listeners may remain; cross-interface rejection not tested"],
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report["checks"], ensure_ascii=False))
        print("report:", args.output)
        return 0 if all(report["checks"].values()) else 1
    finally:
        if zc is not None:
            if registered:
                zc.unregister_service(info)
            zc.close()
        stop.set()
        worker.join(timeout=2)
        witness.close()


if __name__ == "__main__":
    raise SystemExit(main())
