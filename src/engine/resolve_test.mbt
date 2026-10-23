///|
test "smoke: explicit resolve does not depend on PTR and survives initial timeout after success" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.resolve(records[1].name, "wifi", 0, timeout_ms=1000)
  engine.ingest_message(
    message([records[1], records[2], records[3]]),
    "wifi",
    100,
  )
  assert_true(engine.poll_event() is Some(@engine.Seen(_)))
  assert_true(engine.poll_event() is Some(@engine.Resolved(_)))
  engine.advance(1000)
  assert_true(engine.poll_event() is None)
  assert_true(engine.snapshots()[0].complete)
}

///|
test "smoke: timed-out resolve stops questions and late records cannot complete it" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let id = engine.resolve(records[1].name, "wifi", 0, timeout_ms=1000)
  engine.advance(1000)
  match engine.poll_event() {
    Some(@engine.ResolveTimedOut(actual)) => assert_eq(actual, id)
    _ => fail("missing resolve timeout event")
  }
  assert_true(engine.poll_outbound() is None)
  assert_true(engine.next_deadline() is None)
  engine.ingest_message(message(records), "wifi", 1001)
  assert_true(engine.snapshots().is_empty())
  assert_true(engine.poll_event() is None)
}
