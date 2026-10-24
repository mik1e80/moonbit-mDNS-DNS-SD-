# Fixture provenance

`zeroconf-0.148.0-response.hex` is a response from our own synthetic service,
captured by the M0 native probe on 2026-10-23. It contains PTR, TXT, SRV, A and
an opaque NSEC record. No third-party device traffic is included.

Packet SHA256: `ff70b5a3f76802870c90262b338eec5a5d430c4f536c52036733e0737a45f42b`.
The test embeds the same bytes so it can run on JS without filesystem access.
This first fixture validates decoding. Current lifecycle and replay evidence
is recorded separately below.

`live-20261024.jsonl` is a filtered export from an independent
python-zeroconf 0.148.0 process on the same Windows host. The exporter checks
every selected packet's question/record owner and PTR/SRV/NSEC target names
against our synthetic-service allowlist. This recording contained no unrelated
packets, so zero packets were excluded. Packet bytes, seed, scopes and input
times are preserved. The file includes timer commands as well as packets.

The source commit, binary hash, original recording hash, exported fixture hash,
HTTP request, event timeline and eight live checks are in
[`windows-live-20261024.json`](../docs/evidence/windows-live-20261024.json).
Repeated replay of the export produces identical output and the same service
events as the live recording. This is same-host independent-process evidence;
it does not establish second-device or Linux network interoperability.

Reproduce export verification from a local live report:

```powershell
.venv\Scripts\python.exe tests/interop/export_capture.py `
  --report .tools/live-recording-20261024.json `
  --fixture fixtures/live-20261024.jsonl `
  --evidence docs/evidence/windows-live-20261024.json
```
