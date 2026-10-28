///|
test "smoke: engine drains and cancels large known-answer bursts atomically" {
  let records = fixture()
  let engine = @engine.Engine::new(query_capacity=1024, event_capacity=1024)
  let interrupted = @engine.Engine::new(query_capacity=1024, event_capacity=1024)
  let id = engine.browse(records[0].name, "wifi", 0)
  let other_id = interrupted.browse(records[0].name, "wifi", 0)
  let all : Array[@wire.Record] = []
  for i in 0..<260 {
    all.push({
      ..records[0],
      data: @wire.Ptr(@model.DnsName::parse("p-\{i}._http._tcp.local.")),
    })
  }
  for start in [0, 128, 256] {
    let part : Array[@wire.Record] = []
    for i in start..<(start + 128).min(all.length()) {
      part.push(all[i])
    }
    engine.ingest_message(message(part), "wifi", 0)
    interrupted.ingest_message(message(part), "wifi", 0)
  }
  engine.advance(120)
  guard engine.poll_outbound() is Some(first) else { fail("no burst") }
  assert_eq(@wire.decode(first.bytes).flags & 0x0200, 0x0200)
  let mut total = @wire.decode(first.bytes).records.length()
  while engine.stats().queued_datagrams > 0 {
    guard engine.poll_outbound() is Some(next) else {
      fail("lost continuation")
    }
    let packet = @wire.decode(next.bytes)
    assert_true(packet.questions.is_empty())
    total += packet.records.length()
  }
  assert_eq(total, 260)
  engine.advance(1120)
  let _ = engine.poll_outbound()
  engine.cancel(id, 1120)
  assert_true(engine.poll_outbound() is None)
  engine.close()
  interrupted.advance(120)
  guard interrupted.poll_outbound() is Some(started) else { fail("no cancellation burst") }
  assert_eq(@wire.decode(started.bytes).flags & 0x0200, 0x0200)
  assert_true(interrupted.stats().queued_datagrams > 0)
  interrupted.cancel(other_id, 120)
  assert_eq(interrupted.stats().queued_datagrams, 0)
  assert_true(interrupted.poll_outbound() is None)
  assert_true(interrupted.snapshots().is_empty())
}
