///|
test "smoke: query jitter backoff and cancellation use injected time" {
  let records = fixture()
  let engine = @engine.Engine::new(seed=77U)
  let id = engine.browse(records[0].name, "wifi", 0)
  let first = engine.next_deadline().unwrap()
  assert_true(first >= 20L && first <= 120L)
  assert_true(engine.poll_outbound() is None)
  engine.advance(120)
  let query = engine.poll_outbound().unwrap()
  assert_eq(query.rr_type, 12)
  assert_eq(@wire.decode(query.bytes).records.length(), 0)
  assert_eq(engine.next_deadline(), Some(1120L))
  engine.advance(1119)
  assert_true(engine.poll_outbound() is None)
  engine.advance(1120)
  assert_eq(engine.next_deadline(), Some(1120L)) // queued output needs draining
  engine.cancel(id, 1120)
  assert_true(engine.poll_outbound() is None)
  assert_true(engine.next_deadline() is None)
}

///|
test "smoke: cached answers use remaining TTL with class high bit cleared" {
  let records = fixture()
  let engine = @engine.Engine::new(seed=5U)
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message([records[0]]), "wifi", 0)
  engine.advance(120)
  let packet = engine.poll_outbound().unwrap()
  assert_eq(packet.rr_type, 12)
  let query = @wire.decode(packet.bytes)
  assert_eq(query.records.length(), 1)
  assert_eq(query.records[0].ttl, 119U)
  assert_false(query.records[0].cache_flush)
  assert_false(query.questions[0].unicast_response)
}

///|
test "smoke: unique records defer polling until jittered 80 percent refresh" {
  let records = fixture()
  let engine = @engine.Engine::new(seed=5U)
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message(records), "wifi", 0)
  engine.advance(95000)
  while engine.poll_outbound() is Some(query) {
    assert_true(query.rr_type == 12 || query.rr_type == 28)
  }
  engine.advance(98400)
  let types : Array[Int32] = []
  while engine.poll_outbound() is Some(query) {
    types.push(query.rr_type)
    if query.rr_type == 33 {
      assert_eq(@wire.decode(query.bytes).records.length(), 0)
    }
  }
  assert_true(types.contains(33) && types.contains(16) && types.contains(1))
}
