///|
test "smoke: known-answer count ceiling is reachable and follows packet budget" {
  let name = @model.DnsName::from_labels([])
  let record : @wire.Record = {
    name,
    rr_type: 1,
    rr_class: 1,
    cache_flush: false,
    ttl: 120U,
    data: @wire.A(b"\x7f\x00\x00\x01"),
    section: @wire.Answer,
  }
  for budget in [1, 2, 64] {
    let limit = budget * 256 - 1
    let packets = @wire.query_packets(
      name,
      1,
      Array::make(limit, record),
      max_packets=budget,
    )
    assert_eq(packets.length(), budget)
    let mut received = 0
    for i, bytes in packets {
      let packet = @wire.decode(bytes)
      assert_eq(packet.questions.length(), if i == 0 { 1 } else { 0 })
      assert_eq(packet.records.length(), if i == 0 { 255 } else { 256 })
      assert_eq(packet.flags & 0x0200, if i + 1 < budget { 0x0200 } else { 0 })
      assert_true(bytes.length() <= 9000)
      for answer in packet.records {
        assert_true(answer.name.same_name(name))
        assert_true(answer.data is @wire.A(b"\x7f\x00\x00\x01"))
        received += 1
      }
    }
    assert_eq(received, limit)
    let rejected = try {
      let _ = @wire.query_packets(
        name,
        1,
        Array::make(limit + 1, record),
        max_packets=budget,
      )
      false
    } catch {
      @wire.Malformed(detail) =>
        detail == "known-answer count exceeds packet budget"
    }
    assert_true(rejected)
  }
}

///|
test "smoke: known-answer encoding rejects an oversized record and invalid question" {
  let name = @model.DnsName::parse("peer._http._tcp.local.")
  let huge = @model.TxtRecord::from_entries(
    Array::make(36, Bytes::make(250, b'x')),
  )
  let record : @wire.Record = {
    name,
    rr_type: 16,
    rr_class: 1,
    cache_flush: false,
    ttl: 120U,
    data: @wire.Txt(huge),
    section: @wire.Answer,
  }
  assert_true(
    try {
      let _ = @wire.query_packets(name, 16, [record])
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @wire.query_packets(name, 0, [])
      false
    } catch {
      _ => true
    },
  )
}
