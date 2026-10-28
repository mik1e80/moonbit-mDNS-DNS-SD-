///|
test "smoke: oversized known answer falls back to QM and later queries recover" {
  let records = fixture()
  // Exercise the public DTO input: valid model data can exceed a UDP packet.
  let huge = @model.TxtRecord::from_entries(
    Array::make(36, Bytes::make(250, b'x')),
  )
  records[2] = { ..records[2], cache_flush: false, data: @wire.Txt(huge), }
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message(records), "wifi", 0)
  assert_true(engine.poll_event() is Some(@engine.Seen(_)))
  assert_true(engine.poll_event() is Some(@engine.Resolved(_)))
  assert_true(engine.poll_event() is None)
  engine.advance(120)
  let sent : Array[Int32] = []
  while engine.poll_outbound() is Some(outbound) {
    let packet = @wire.decode(outbound.bytes)
    assert_eq(packet.questions.length(), 1)
    assert_false(packet.questions[0].unicast_response)
    sent.push(outbound.rr_type)
    if outbound.rr_type == 16 {
      assert_true(packet.records.is_empty())
      assert_eq(packet.flags & 0x0200, 0)
    }
  }
  assert_true(sent.contains(12))
  assert_true(sent.contains(16))
  assert_true(sent.contains(28))
  assert_true(
    engine.poll_event() is Some(@engine.Diagnostic("known_answer_limit", _)),
  )
  assert_true(engine.poll_event() is None)
  assert_eq(engine.stats().queued_datagrams, 0)
  assert_eq(engine.stats().queued_questions, 0)
  assert_eq(engine.stats().dropped_events, 0)
  assert_true(engine.snapshots()[0].complete)

  let fresh = fixture()[2]
  guard fresh.data is @wire.Txt(expected) else { fail("fixture TXT missing") }
  engine.ingest_message(
    message([{ ..records[2], ttl: 0U, }, { ..fresh, cache_flush: false, }]),
    "wifi",
    200,
  )
  assert_true(engine.poll_event() is Some(@engine.Updated(_, "response")))
  engine.advance(1120)
  let mut recovered = false
  while engine.poll_outbound() is Some(outbound) {
    if outbound.rr_type == 16 {
      let packet = @wire.decode(outbound.bytes)
      assert_eq(packet.records.length(), 1)
      assert_true(
        packet.records[0].data is @wire.Txt(txt) &&
        txt.to_wire() == expected.to_wire(),
      )
      recovered = true
    }
  }
  assert_true(recovered)
  assert_true(engine.poll_event() is None)
  engine.close()
  assert_true(engine.poll_outbound() is None)
}
