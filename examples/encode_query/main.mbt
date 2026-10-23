///|
fn main raise {
  let name = @dnssd.DnsName::from_utf8_labels(["_http", "_tcp", "local"])
  let packet = @dnssd.qm_query(name, 12)
  let decoded = @dnssd.decode_packet(packet)
  println(
    "QM PTR query: \{decoded.questions[0].name.to_presentation()} (\{packet.length()} bytes)",
  )
}
