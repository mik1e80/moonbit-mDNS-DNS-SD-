///|
test "smoke: known-answer bursts keep one question and complete TC continuation chain" {
  let name = @model.DnsName::parse("_http._tcp.local.")
  let answers : Array[@wire.Record] = []
  for i in 0..<300 {
    answers.push({
      name,
      rr_type: 12,
      rr_class: 1,
      ttl: 120U,
      cache_flush: true,
      data: @wire.Ptr(@model.DnsName::parse("p-\{i}._http._tcp.local.")),
      section: @wire.Answer,
    })
  }
  let packets = @wire.query_packets(name, 12, answers, max_size=512)
  assert_true(packets.length() > 1)
  let mut received = 0
  for i, bytes in packets {
    assert_true(bytes.length() <= 512)
    let packet = @wire.decode(bytes)
    assert_eq(packet.questions.length(), if i == 0 { 1 } else { 0 })
    assert_eq(
      packet.flags & 0x0200,
      if i + 1 < packets.length() {
        0x0200
      } else {
        0
      },
    )
    for record in packet.records {
      assert_false(record.cache_flush)
      assert_true(
        record.data is @wire.Ptr(target) &&
        target.same_name(
          @model.DnsName::parse("p-\{received}._http._tcp.local."),
        ),
      )
      received += 1
    }
  }
  assert_eq(received, 300)
  let bounded = try {
    let _ = @wire.query_packets(name, 12, answers, max_size=512, max_packets=1)
    false
  } catch {
    _ => true
  }
  assert_true(bounded)
}
