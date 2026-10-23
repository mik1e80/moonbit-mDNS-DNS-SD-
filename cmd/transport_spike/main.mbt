///|
// M0 capability probe, not a production transport or service browser.
async fn main {
  let args = @env.args()
  guard args.length() == 3 else {
    fail("usage: transport_spike <interface-ipv4> <multicast|ordinary>")
  }
  let iface = @socket.Addr::parse(args[1] + ":0")
  let group = @socket.Addr::parse("224.0.0.251:5353")
  let mode = args[2]
  guard mode == "multicast" || mode == "ordinary" else {
    fail("mode must be multicast or ordinary")
  }
  let server = if mode == "multicast" {
    @socket.UdpServer::multicast(group, interface_addr=iface)
  } else {
    let s = @socket.UdpServer(@socket.Addr::parse("0.0.0.0:5353"))
    errdefer s.close()
    s.join_multicast_group(group, interface_addr=iface)
    s
  }
  defer server.close()
  server.set_multicast_interface(iface)
  server.set_multicast_ttl(255)
  println("bound=\{server.addr} mode=\{mode} interface=\{args[1]}")
  // ID=0, one QM PTR question for _http._tcp.local.
  let question : Bytes = b"\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x05_http\x04_tcp\x05local\x00\x00\x0c\x00\x01"
  try server.sendto(question, group) catch {
    error => println("send_error=\{error}")
  } noraise {
    _ => println("query_sent source_port=5353 bytes=\{question.length()}")
  }
  let buf = FixedArray::make(9000, b'\x00')
  let received = @async.with_timeout_opt(3000, () => {
    for _ in 0..<64 {
      let (n, peer) = server.recvfrom(buf)
      if n >= 12 && (buf[2].to_int() & 0x80) != 0 {
        return Some((n, peer))
      }
    }
    None
  })
  match received {
    Some(Some((n, peer))) =>
      println(
        "response_received bytes=\{n} peer=\{peer} ingress_interface=unavailable",
      )
    _ => println("no_response_in_window milliseconds=3000")
  }
}
