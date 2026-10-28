///|
test "smoke: replay is deterministic and cancellation clears queued questions" {
  let a = @replay.Replay::new(seed=7U)
  let b = @replay.Replay::new(seed=7U)
  let commands = [
    "{\"kind\":\"browse\",\"at_ms\":0,\"scope\":\"demo\",\"name\":\"_http._tcp.local.\"}",
    "{\"kind\":\"advance\",\"at_ms\":120}", "{\"kind\":\"cancel\",\"at_ms\":200,\"id\":1}",
    "{\"kind\":\"advance\",\"at_ms\":5000}",
  ]
  for command in commands {
    assert_eq(a.step_line(command), b.step_line(command))
  }
  assert_true(a.engine.next_deadline() is None)
}

///|
test "smoke: damaged packets emit diagnostics and backward replay time is rejected" {
  let replay = @replay.Replay::new()
  let events = replay.step_line(
    "{\"kind\":\"packet\",\"at_ms\":10,\"scope\":\"demo\",\"packet_hex\":\"00\"}",
  )
  assert_eq(events.length(), 1)
  assert_true(
    events[0] is { "event": "diagnostic", "code": "packet_rejected", .. },
  )
  let invalid = try {
    let _ = replay.step_line("{\"kind\":\"advance\",\"at_ms\":9}")
    false
  } catch {
    _ => true
  }
  assert_true(invalid)
}

///|
test "smoke: replay returns polling diagnostics with the same frame and fallback" {
  let replay = @replay.Replay::new()
  let _ = replay.step_line(
    "{\"kind\":\"resolve\",\"at_ms\":0,\"scope\":\"wifi\",\"name\":\"peer._http._tcp.local.\"}",
  )
  // This legal response fits 9000 bytes; adding the query's question makes
  // the same uncompressed known answer too large for an outbound packet.
  let entries = Array::make(35, Bytes::make(254, b'x'))
  entries.push(Bytes::make(10, b'y'))
  let data = @model.TxtRecord::from_entries(entries).to_wire()
  let bytes = b"\x00\x00\x84\x00\x00\x00\x00\x01\x00\x00\x00\x00".to_array()
  for byte in @model.DnsName::parse("peer._http._tcp.local.").to_wire() {
    bytes.push(byte)
  }
  for byte in b"\x00\x10\x00\x01\x00\x00\x00\x78" {
    bytes.push(byte)
  }
  bytes.push((data.length() >> 8).to_byte())
  bytes.push((data.length() & 255).to_byte())
  for byte in data {
    bytes.push(byte)
  }
  assert_true(bytes.length() <= 9000)
  let hex = @model.bytes_hex(Bytes::makei(bytes.length(), i => bytes[i]))
  let accepted = replay.step_line(
    "{\"kind\":\"packet\",\"at_ms\":0,\"scope\":\"wifi\",\"packet_hex\":\"\{hex}\"}",
  )
  assert_false(accepted.any(event => event is { "event": "diagnostic", .. }))
  let events = replay.step_line("{\"kind\":\"advance\",\"at_ms\":120}")
  assert_eq(
    events
    .filter(event => {
      event
      is {
        "event": "diagnostic",
        "code": "known_answer_limit",
        "at_ms": 120,
        ..
      }
    })
    .length(),
    1,
  )
  assert_true(
    events.any(event => {
      event is { "event": "outbound", "rr_type": 16, "at_ms": 120, .. }
    }),
  )
  assert_true(replay.engine.poll_event() is None)
  assert_true(
    replay.step_line("{\"kind\":\"advance\",\"at_ms\":121}").is_empty(),
  )
}
