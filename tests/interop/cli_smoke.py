"""Lightweight binary contract tests, with no network required."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXE = ROOT / "_build/native/debug/build/cmd/moondiscover/moondiscover.exe"


def run(*args):
    return subprocess.run([str(EXE), *args], capture_output=True, text=True, timeout=5)


def main():
    trace = ROOT / "fixtures/replay-basic.jsonl"
    a = run("replay", "--file", str(trace), "--seed", "7")
    b = run("replay", "--file", str(trace), "--seed", "7")
    assert a.returncode == b.returncode == 0, (a.stderr, b.stderr)
    events = [json.loads(line) for line in a.stdout.splitlines()]
    assert events == [json.loads(line) for line in b.stdout.splitlines()]
    resolved = [e for e in events if e["event"] == "resolved"]
    assert len(resolved) == 1 and resolved[0]["service"]["port"] == 43219
    assert any(e["event"] == "unavailable" and e["reason"] == "ttl_expired" for e in events)
    assert any(e["event"] == "removed" and e["reason"] == "ttl_expired" and e["service"]["remaining_ttl_ms"] == 0 and not e["service"]["complete"] for e in events)
    bad = run("browse", "--invalid", "x")
    assert bad.returncode != 0 and json.loads(bad.stdout)["event"] == "error"
    assert run("--help").returncode == 0
    assert run("--version").stdout.strip() == "0.1.0-dev"
    print(json.dumps({"deterministic_replay": True, "resolved_endpoint": True, "expiry_events": True, "invalid_args_exit": True, "help_version": True}))


if __name__ == "__main__":
    main()
