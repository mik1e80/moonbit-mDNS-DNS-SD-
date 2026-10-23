///|
test "smoke: mDNS accepts 255 octets plus root terminator but rejects 257 total" {
  let label = Bytes::make(63, b'a')
  let name = @model.DnsName::from_labels([
    label,
    label,
    label,
    Bytes::make(62, b'b'),
  ])
  assert_eq(name.to_wire().length(), 256)
  let invalid = try {
    let _ = @model.DnsName::from_labels([label, label, label, label])
    false
  } catch {
    _ => true
  }
  assert_true(invalid)
}
