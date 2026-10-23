///|
test "smoke: UTF-8 instance label keeps literal dot and wire octets" {
  let name = @model.DnsName::from_utf8_labels([
    "中文.服务", "_http", "_tcp", "local",
  ])
  assert_eq(
    name.labels()[0],
    b"\xe4\xb8\xad\xe6\x96\x87.\xe6\x9c\x8d\xe5\x8a\xa1",
  )
  assert_eq(name.to_wire()[0].to_int(), 13)
  assert_eq(name.labels().length(), 4)
  let split = @model.DnsName::from_utf8_labels([
    "中文", "服务", "_http", "_tcp", "local",
  ])
  assert_false(name.same_name(split))
  let a = @model.DnsName::from_utf8_labels(["Printer", "LOCAL"])
  let b = @model.DnsName::from_utf8_labels(["printer", "local"])
  assert_true(a.same_name(b))
  assert_eq(a.to_presentation(), "Printer.LOCAL.")
}

///|
test "smoke: TXT preserves binary, flag, empty value and first duplicate" {
  let txt = @model.TxtRecord::from_entries([
    b"flag", b"empty=", b"blob=\x00\xff", b"KEY=first", b"key=second",
  ])
  let decoded = @model.TxtRecord::from_wire(txt.to_wire())
  assert_eq(decoded.entries(), txt.entries())
  assert_eq(decoded.lookup("flag"), @model.Flag)
  assert_eq(decoded.lookup("empty"), @model.Value(b""))
  assert_eq(decoded.lookup("blob"), @model.Value(b"\x00\xff"))
  assert_eq(decoded.lookup("key"), @model.Value(b"first"))
  assert_eq(decoded.lookup("absent"), @model.Missing)
}

///|
test "smoke: malformed model input is rejected" {
  let empty = Some(@model.DnsName::from_labels([b""])) catch { _ => None }
  let long_label = Some(@model.DnsName::from_labels([Bytes::make(64, b'a')])) catch {
    _ => None
  }
  let truncated = Some(@model.TxtRecord::from_wire(b"\x05abc")) catch {
    _ => None
  }
  let long_txt = Some(@model.TxtRecord::from_entries([Bytes::make(256, b'a')])) catch {
    _ => None
  }
  assert_true(empty is None)
  assert_true(long_label is None)
  assert_true(truncated is None)
  assert_true(long_txt is None)
}
