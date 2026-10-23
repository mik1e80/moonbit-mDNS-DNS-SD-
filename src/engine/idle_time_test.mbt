///|
test "smoke: idle timer ticks keep live remaining TTL without content events" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message(records), "wifi", 0)
  let _ = engine.poll_event()
  let _ = engine.poll_event()
  engine.advance(1000)
  assert_eq(engine.snapshots()[0].remaining_ttl_ms, 119000L)
  assert_true(engine.poll_event() is None)
  engine.advance(2000)
  assert_eq(engine.snapshots()[0].remaining_ttl_ms, 118000L)
}
