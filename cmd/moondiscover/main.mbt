///|
fn usage() -> Unit {
  println(
    "MoonDiscover 0.1.0-dev\n  browse --interface IPV4 --service _http._tcp.local. [--duration-ms 5000]\n  resolve --interface IPV4 --instance 'Demo._http._tcp.local.' [--duration-ms 5000]\n  doctor --interface IPV4\n  replay --file trace.jsonl [--seed 1]\nNames support DNS presentation escaping. JSONL is written to stdout.",
  )
}

///|
fn options(args : Array[String]) -> Map[String, String] raise {
  let result : Map[String, String] = Map([])
  let allowed = [
    "--interface", "--service", "--instance", "--duration-ms", "--file", "--seed",
  ]
  let mut i = 2
  while i < args.length() {
    let key = args[i]
    guard allowed.contains(key) &&
      i + 1 < args.length() &&
      !result.contains(key) else {
      fail("unknown, duplicate or incomplete option: " + key)
    }
    result[key] = args[i + 1]
    i += 2
  }
  result
}

///|
fn required(options : Map[String, String], key : String) -> String raise {
  match options.get(key) {
    Some(value) => value
    None => fail("missing option: " + key)
  }
}

///|
fn number(text : String, maximum : Int32) -> Int32 raise {
  guard text.length() > 0 && text.length() <= 10 else {
    fail("invalid decimal integer")
  }
  let mut value = 0L
  for c in text {
    guard c >= '0' && c <= '9' else { fail("invalid decimal integer") }
    value = value * 10L + (c.to_int() - 48).to_int64()
    guard value <= maximum.to_int64() else {
      fail("integer exceeds option limit")
    }
  }
  value.to_int()
}

///|
fn interface_ipv4(options : Map[String, String]) -> UInt32 raise {
  let address = @socket.Addr::parse(required(options, "--interface") + ":0")
  guard !address.is_ipv6() else {
    fail("an explicit IPv4 interface is required")
  }
  address.ip()
}

///|
async fn run_command(args : Array[String]) -> Unit {
  if args.length() < 2 || args[1] == "--help" || args[1] == "help" {
    usage()
    return
  }
  if args[1] == "--version" {
    println("0.1.0-dev")
    return
  }
  let options = options(args)
  match args[1] {
    "doctor" => {
      let ip = interface_ipv4(options)
      let first = @native.MulticastSocket::open(ip)
      defer first.close()
      let second = @native.MulticastSocket::open(ip)
      second.close()
      println(
        Json::object({
          "event": Json("doctor"),
          "interface_index": Json(first.interface_index),
          "port": Json(5353),
          "shared_bind": Json(true),
          "mode": Json("ipv4_qm_multicast_only"),
          "network_response_tested": Json(false),
        }).stringify(),
      )
    }
    "replay" => {
      let path = required(options, "--file")
      guard @fs.file_size(path) <= 8388608L else {
        fail("replay file exceeds 8 MiB")
      }
      let data = @fs.read_file(path)
      let content = data.text()
      let seed = number(options.get("--seed").unwrap_or("1"), 2147483647).reinterpret_as_uint()
      let replay = @dnssd.Replay::new(seed~)
      let mut count = 0
      for line in content.split("\n") {
        let line = line.trim().to_owned()
        if line == "" {
          continue
        }
        count += 1
        guard count <= 10000 else { fail("replay command count exceeds 10000") }
        for event in replay.step_line(line) {
          println(event.stringify())
        }
      }
    }
    "browse" | "resolve" => {
      let duration = number(
        options.get("--duration-ms").unwrap_or("5000"),
        3600000,
      )
      guard duration > 0 else { fail("duration must be positive") }
      let browser = @native.Browser::open(interface_ipv4(options))
      defer browser.close()
      if args[1] == "browse" {
        for service in required(options, "--service").split(",") {
          let _ = browser.browse(@dnssd.DnsName::parse(service.to_owned()))
        }
      } else {
        let _ = browser.resolve(
          @dnssd.DnsName::parse(required(options, "--instance")),
          timeout_ms=duration,
        )
      }
      let mut seen = 0
      let mut resolved = 0
      browser.run(duration, event => {
        match event {
          @dnssd.Event::Seen(_) => seen += 1
          @dnssd.Event::Resolved(_) => resolved += 1
          _ => ()
        }
        println(@dnssd.event_json(event).stringify())
      })
      while browser.poll_event() is Some(event) {
        println(@dnssd.event_json(event).stringify())
      }
      println(
        Json::object({
          "event": Json("summary"),
          "seen_events": Json(seen),
          "resolved_events": Json(resolved),
          "duration_ms": Json(duration),
          "observation": Json(
            if seen == 0 {
              "no_service_observed_in_window"
            } else {
              "services_observed"
            },
          ),
        }).stringify(),
      )
      if args[1] == "resolve" && resolved == 0 {
        fail("instance was not resolved within the observation window")
      }
    }
    _ => fail("unknown command: " + args[1])
  }
}

///|
async fn main {
  let failure = try {
    run_command(@env.args())
    None
  } catch {
    error => Some(error)
  }
  if failure is Some(error) {
    println(
      Json::object({ "event": Json("error"), "message": Json("\{error}") }).stringify(),
    )
    raise error
  }
}
