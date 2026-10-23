///|
test "smoke: QM query has no QU bit and roundtrips labels" {
  let name = @model.DnsName::from_utf8_labels(["_http", "_tcp", "local"])
  let packet = @wire.qm_query(name, 12)
  let decoded = @wire.decode(packet)
  assert_eq(decoded.id, 0)
  assert_eq(decoded.flags, 0)
  assert_eq(decoded.questions.length(), 1)
  assert_false(decoded.questions[0].unicast_response)
  assert_eq(decoded.questions[0].rr_class, 1)
  assert_true(decoded.questions[0].name.same_name(name))
}

///|
test "smoke: compressed PTR class high bit and TTL remain distinct" {
  let packet : Bytes = b"\x00\x00\x84\x00\x00\x00\x00\x01\x00\x00\x00\x00\x05_http\x04_tcp\x05local\x00\x00\x0c\x80\x01\xff\xff\xff\xff\x00\x07\x04demo\xc0\x0c"
  let message = @wire.decode(packet)
  assert_eq(message.records.length(), 1)
  let rr = message.records[0]
  assert_true(rr.cache_flush)
  assert_eq(rr.rr_class, 1)
  assert_eq(rr.ttl, 0xffffffffU)
  match rr.data {
    @wire.Ptr(name) =>
      assert_eq(name.to_presentation(), "demo._http._tcp.local.")
    _ => fail("expected PTR")
  }
}

///|
test "smoke: malformed lengths pointers and record budgets are bounded" {
  let short = Some(@wire.decode(b"\x00")) catch { _ => None }
  let looped = Some(@wire.decode_name(b"\xc0\x00", 0)) catch { _ => None }
  let truncated = Some(@wire.decode_name(b"\x05abc", 0)) catch { _ => None }
  let count = Some(
    @wire.decode(b"\x00\x00\x84\x00\xff\xff\x00\x00\x00\x00\x00\x00"),
  ) catch {
    _ => None
  }
  assert_true(short is None)
  assert_true(looped is None)
  assert_true(truncated is None)
  assert_true(count is None)
}

///|
test "smoke: unknown RR can precede A without losing alignment" {
  let packet : Bytes = b"\x00\x00\x84\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\xff\x00\x00\x01\x00\x00\x00\x01\x00\x02xy\x00\x00\x01\x00\x01\x00\x00\x00\x01\x00\x04\x7f\x00\x00\x01"
  let message = @wire.decode(packet)
  assert_eq(message.records.length(), 2)
  assert_true(message.records[0].data is @wire.Unknown(_))
  assert_true(message.records[1].data is @wire.A(b"\x7f\x00\x00\x01"))
}
