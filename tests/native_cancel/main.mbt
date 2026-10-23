///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    fail("usage: native_cancel <interface-ipv4>")
  }
  let ip = @socket.Addr::parse(args[1] + ":0").ip()
  let browser = @native.Browser::open(ip)
  let result = @async.with_timeout_opt(25, () => browser.run(5000, _ => ()))
  guard result is None else { fail("expected cancellation") }
  let closed = try {
    let _ = browser.poll()
    false
  } catch {
    _ => true
  }
  guard closed else { fail("cancelled browser was not closed") }
  let reopened = @native.Browser::open(ip)
  reopened.close()
  println("{\"cancelled_run_closed\":true,\"reopened\":true}")
}
