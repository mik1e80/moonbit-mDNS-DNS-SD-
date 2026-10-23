///|
test "smoke: public root API constructs a DNS-SD question" {
  let name = @dnssd.DnsName::from_utf8_labels(["_http", "_tcp", "local"])
  let message = @dnssd.decode_packet(@dnssd.qm_query(name, 12))
  assert_true(message.questions[0].name.same_name(name))
  assert_eq(message.questions[0].rr_type, 12)
}
