# Fixture provenance

`zeroconf-0.148.0-response.hex` is a response from our own synthetic service,
captured by the M0 native probe on 2026-10-23. It contains PTR, TXT, SRV, A and
an opaque NSEC record. No third-party device traffic is included.

Packet SHA256: `ff70b5a3f76802870c90262b338eec5a5d430c4f536c52036733e0737a45f42b`.
The test embeds the same bytes so it can run on JS without filesystem access.
The data is a real-network decoder regression fixture, not evidence of a
completed cache, query engine or deterministic event replay system.
