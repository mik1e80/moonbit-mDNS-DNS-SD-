///|
fn hex(data : Bytes) -> String {
  let out = StringBuilder()
  let digits = "0123456789abcdef"
  for b in data {
    out.write_char(digits[b.to_int() >> 4].unsafe_to_char())
    out.write_char(digits[b.to_int() & 15].unsafe_to_char())
  }
  out.to_string()
}

///|
fn main raise {
  let args = @env.args()
  guard args.length() == 2 else { fail("usage: native_spike <interface-ipv4>") }
  let iface = @socket.Addr::parse(args[1] + ":0")
  guard !iface.is_ipv6() else { fail("IPv4 interface required") }
  let socket = @native.MulticastSocket::open(iface.ip())
  defer socket.close()
  // A second live socket confirms coexistence with this implementation.
  let other = @native.MulticastSocket::open(iface.ip())
  other.close()
  other.close()
  println("{\"event\":\"bound\",\"port\":5353,\"second_bind\":true}")
  let name = @model.DnsName::from_utf8_labels(["_http", "_tcp", "local"])
  let question = @wire.qm_query(name, 12)
  socket.send(question)
  println("{\"event\":\"sent\",\"hex\":\"\{hex(question)}\"}")
  // Bounded observation: max ~4 seconds, max 128 datagrams.
  for _ in 0..<128 {
    match socket.receive(timeout_ms=30) {
      None => ()
      Some(packet) => {
        let source = @socket.Addr::new(packet.source_ipv4, packet.source_port)
        let dest = @socket.Addr::new(packet.destination_ipv4, 5353)
        let count = @wire.decode(packet.bytes).records.length() catch {
          _ => -1
        }
        println(
          "{\"event\":\"packet\",\"source\":\"\{source}\",\"destination\":\"\{dest}\",\"interface_index\":\{packet.interface_index},\"decoded_records\":\{count},\"hex\":\"\{hex(packet.bytes)}\"}",
        )
      }
    }
  }
  socket.close()
  let reopened = @native.MulticastSocket::open(iface.ip())
  reopened.close()
  println("{\"event\":\"closed\",\"rebind\":true}")
}
