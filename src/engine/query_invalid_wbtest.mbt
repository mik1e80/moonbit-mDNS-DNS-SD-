///|
test "smoke: an invalid queued question is diagnosed without blocking a valid peer" {
  let engine = Engine::new()
  let name = @model.DnsName::parse("_http._tcp.local.")
  // Scheduling only generates valid types; inject a broken internal job to
  // exercise the defensive error branch independently of Known Answers.
  engine.pending.push({ scope: "wifi", name, rr_type: 0, })
  engine.pending.push({ scope: "wifi", name, rr_type: 12, })
  guard engine.poll_outbound() is Some(outbound) else {
    fail("valid question after invalid job was lost")
  }
  assert_eq(outbound.rr_type, 12)
  let packet = @wire.decode(outbound.bytes)
  assert_eq(packet.questions.length(), 1)
  assert_eq(packet.questions[0].rr_type, 12)
  assert_true(packet.records.is_empty())
  assert_true(engine.poll_event() is Some(Diagnostic("query_invalid", _)))
  assert_true(engine.poll_event() is None)
  assert_true(engine.poll_outbound() is None)
  assert_eq(engine.stats().queued_questions, 0)
  assert_eq(engine.stats().queued_datagrams, 0)
}
