"""Short native regression: oversized multicast must not end service browsing."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import platform
import socket
import struct
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def name(*labels):
    return b"".join(bytes([len(label)]) + label for label in labels) + b"\0"


def record(owner, kind, payload, unique=False):
    return owner + struct.pack("!HHIH", kind, 0x8001 if unique else 1, 120,
                               len(payload)) + payload


def response(token, interface):
    service = name(b"_http", b"_tcp", b"local")
    instance = name(token, b"_http", b"_tcp", b"local")
    host = name(token, b"local")
    txt = b"demo=" + token
    return (struct.pack("!HHHHHH", 0, 0x8400, 0, 1, 0, 3)
            + record(service, 12, instance)
            + record(instance, 33, struct.pack("!HHH", 0, 0, 18080) + host, True)
            + record(instance, 16, bytes([len(txt)]) + txt, True)
            + record(host, 1, socket.inet_aton(interface), True))


def sender(interface, port):
    result = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        result.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        result.bind(("", port))
        result.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF,
                          socket.inet_aton(interface))
        result.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
        return result
    except BaseException:
        result.close()
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--interface", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    binary = ROOT / "_build/native/debug/build/cmd/moondiscover/moondiscover"
    if platform.system() == "Windows":
        binary = binary.with_suffix(".exe")
    token = ("oversized-" + uuid.uuid4().hex[:10]).encode()
    target = ("224.0.0.251", 5353)
    git = ["git", "-c", "safe.directory=" + ROOT.as_posix()]
    provenance = {
        "date": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "source_commit": subprocess.check_output(
            [*git, "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_dirty": bool(subprocess.check_output(
            [*git, "status", "--porcelain"], cwd=ROOT, text=True).strip()),
        "cli_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "platform": platform.platform(),
        "oversized_datagram_lengths": [9001, 16000],
    }
    process = subprocess.Popen(
        [str(binary), "browse", "--interface", args.interface, "--service",
         "_http._tcp.local.", "--duration-ms", "1800"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        with sender(args.interface, 0) as bad, sender(args.interface, 5353) as good:
            time.sleep(0.25)
            # Ephemeral source port also proves rejection precedes filtering.
            bad.sendto(b"x" * 9001, target)
            time.sleep(0.1)
            bad.sendto(b"x" * 16000, target)
            time.sleep(0.1)
            survived = process.poll() is None
            packet = response(token, args.interface)
            for _ in range(3):
                good.sendto(packet, target)
                time.sleep(0.05)
        stdout, stderr = process.communicate(timeout=4)
        received = [json.loads(line) for line in stdout.splitlines()
                    if line.startswith("{")]
        # Publish only this test's own service, plus process-level diagnostics.
        events = [event for event in received
                  if event.get("service", {}).get("instance_label") == token.decode()
                  or ("service" not in event
                      and event.get("event") in ("summary", "error"))]
        checks = {
            "survived_oversized_datagrams": survived,
            "later_valid_service_resolved": any(
                event.get("event") == "resolved"
                and event.get("service", {}).get("instance_label") == token.decode()
                for event in events),
            "normal_exit": process.returncode == 0,
            "completed_observation_window": any(
                event.get("event") == "summary" for event in events),
        }
        report = {**provenance, "checks": checks, "exit_code": process.returncode,
                  "events": events, "stderr": stderr,
                  "interface_ipv4": args.interface,
                  "limits": ["same-host IPv4 multicast regression"]}
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(checks))
        return 0 if all(checks.values()) else 1
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
