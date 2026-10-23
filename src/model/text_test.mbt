///|
test "smoke: escaped UTF-8 presentation roundtrips binary and dotted labels" {
  let original = @model.DnsName::from_labels([
    b"a.\\\x00\xff", b"_http", b"_tcp", b"local",
  ])
  assert_eq(
    @model.DnsName::parse(original.to_presentation()).labels(),
    original.labels(),
  )
  let unicode = @model.DnsName::parse("中文\\.服务._http._tcp.local.")
  assert_eq(unicode.labels().length(), 4)
  assert_eq(@model.bytes_from_hex(@model.bytes_hex(b"\x00\xff")), b"\x00\xff")
  assert_eq(@model.address_text(b"\x7f\x00\x00\x01"), "127.0.0.1")
  let invalid = try {
    let _ = @model.DnsName::parse("bad\\12")
    false
  } catch {
    _ => true
  }
  assert_true(invalid)
}
