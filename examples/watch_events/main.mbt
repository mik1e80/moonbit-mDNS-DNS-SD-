///|
async fn main {
  let args = @env.args()
  guard args.length() == 3 else {
    fail("usage: watch_events <interface-ipv4> <service-type>")
  }
  let interface = @socket.Addr::parse(args[1] + ":0")
  guard !interface.is_ipv6() else { fail("IPv4 required") }
  let browser = @native.Browser::open(interface.ip())
  defer browser.close()
  let _ = browser.browse(@dnssd.DnsName::parse(args[2]))
  browser.run(5000, event => {
    @stdio.stdout.write(@dnssd.event_json(event).stringify() + "\n")
  })
}
