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
