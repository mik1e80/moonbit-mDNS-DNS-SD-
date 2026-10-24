"""Export only our synthetic service packets, then verify the public replay.

Requires the independent zeroconf tool pinned in requirements.txt. Packet bytes
and timing commands are preserved; an unexpected mixed-service packet aborts.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

from zeroconf._protocol.incoming import DNSIncoming

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))
    assert all(report["checks"].values()), "live experiment did not pass"
    source = ROOT / report["trace_file"]
    raw = source.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == report["trace_sha256"]
    allowed = {"_http._tcp.local.", report["demo"] + ".local.",
               report["demo"] + "._http._tcp.local."}
    frames = [json.loads(line) for line in raw.decode("utf-8").splitlines()]
    kept = []
    excluded = 0
    for frame in frames:
        if frame["kind"] == "packet":
            packet = bytes.fromhex(frame["packet_hex"])
            if report["demo"].encode() not in packet:
                excluded += 1
                continue
            incoming = DNSIncoming(packet)
            records = incoming.answers()
            assert incoming.valid and records, "invalid selected packet"
            assert all(q.name in allowed for q in incoming.questions)
            for record in records:
                assert record.name in allowed, "mixed-service packet"
                for field in ("alias", "server", "next_name"):
                    assert not hasattr(record, field) or getattr(record, field) in allowed
        kept.append(frame)
    args.fixture.parent.mkdir(parents=True, exist_ok=True)
    exported = ("\n".join(json.dumps(f, separators=(",", ":")) for f in kept) + "\n").encode()
    args.fixture.write_bytes(exported)
    binary = ROOT / "_build/native/debug/build/cmd/moondiscover/moondiscover.exe"
    command = [str(binary), "replay", "--file", str(args.fixture.resolve())]
    a = subprocess.run(command, capture_output=True, text=True, timeout=10, check=True)
    b = subprocess.run(command, capture_output=True, text=True, timeout=10, check=True)
    assert a.stdout == b.stdout, "repeated replay differs"
    events = [json.loads(line) for line in a.stdout.splitlines()]
    own = []
    for event in events:
        if event.get("service", {}).get("instance", "").startswith(report["demo"] + "."):
            own.append({k: v for k, v in event.items() if k != "at_ms"})
    assert own == report["replay_service_events"], "public export changed service events"
    report["public_export"] = {
        "fixture": args.fixture.resolve().relative_to(ROOT).as_posix(),
        "sha256": hashlib.sha256(exported).hexdigest(),
        "frames": len(kept),
        "excluded_packets": excluded,
        "record_names_allowlisted": sorted(allowed),
        "packet_bytes_and_times_preserved": True,
        "repeated_replay_identical": True,
        "service_events_match_live_recording": True,
    }
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report["public_export"]))


if __name__ == "__main__":
    main()
