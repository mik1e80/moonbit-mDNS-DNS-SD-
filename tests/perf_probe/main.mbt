///|
fn records(index : Int32) -> Array[@dnssd.Record] raise {
  let service = @dnssd.DnsName::parse("_http._tcp.local.")
  let instance = @dnssd.DnsName::from_utf8_labels([
    "perf-\{index}",
    "_http",
    "_tcp",
    "local",
  ])
  let host = @dnssd.DnsName::from_utf8_labels(["perf-\{index}", "local"])
  let txt = @dnssd.TxtRecord::from_entries([b"demo=performance"])
  [
    {
      name: service,
      rr_type: 12,
      rr_class: 1,
      cache_flush: false,
      ttl: 7200U,
      data: @dnssd.RData::Ptr(instance),
      section: @dnssd.Section::Answer,
    },
    {
      name: instance,
      rr_type: 33,
      rr_class: 1,
      cache_flush: true,
      ttl: 7200U,
      data: @dnssd.RData::Srv(0, 0, 18080, host),
      section: @dnssd.Section::Additional,
    },
    {
      name: instance,
      rr_type: 16,
      rr_class: 1,
      cache_flush: true,
      ttl: 7200U,
      data: @dnssd.RData::Txt(txt),
      section: @dnssd.Section::Additional,
    },
    {
      name: host,
      rr_type: 1,
      rr_class: 1,
      cache_flush: true,
      ttl: 7200U,
      data: @dnssd.RData::A(b"\x0a\x00\x00\x01"),
      section: @dnssd.Section::Additional,
    },
  ]
}

///|
fn main raise {
  let args = @env.args()
  guard args.length() == 2 else { fail("usage: perf_probe <50|200|500>") }
  let size = match args[1] {
    "50" => 50
    "200" => 200
    "500" => 500
    _ => fail("unsupported bounded workload")
  }
  let batches : Array[@dnssd.Message] = []
  let mut group : Array[@dnssd.Record] = []
  for i in 0..<size {
    for record in records(i) {
      group.push(record)
    }
    if group.length() >= 128 || i == size - 1 {
      batches.push({ id: 0, flags: 0x8400, questions: [], records: group, })
      group = []
    }
  }
  let engine = @dnssd.Engine::new(
    cache_capacity=size * 4 + 4,
    service_capacity=size + 1,
    event_capacity=size * 2 + 8,
    query_capacity=size * 4 + 4,
    seed=7U,
  )
  let _ = engine.browse(@dnssd.DnsName::parse("_http._tcp.local."), "perf", 0)
  let started = @transport.monotonic_ms()
  let mut event_peak = 0
  for packet in batches {
    engine.ingest_message(packet, "perf", 0)
    event_peak = event_peak.max(engine.stats().queued_events)
  }
  let ingest_ms = @transport.monotonic_ms() - started
  let initial = engine.stats()
  guard initial.cached_records == size * 4 && initial.services == size else {
    fail("service/cache counts differ from workload")
  }
  guard engine.snapshots().all(s => s.complete) else {
    fail("incomplete service")
  }
  let mut seen = 0
  let mut resolved = 0
  while engine.poll_event() is Some(event) {
    match event {
      @dnssd.Event::Seen(_) => seen += 1
      @dnssd.Event::Resolved(_) => resolved += 1
      _ => fail("unexpected initial event")
    }
  }
  guard seen == size && resolved == size else { fail("missing initial events") }
  let repeated = @transport.monotonic_ms()
  for packet in batches {
    engine.ingest_message(packet, "perf", 1000)
  }
  let repeat_ms = @transport.monotonic_ms() - repeated
  guard engine.poll_event() is None && engine.stats().cached_records == size * 4 else {
    fail("duplicates changed content or grew cache")
  }
  let idle = @transport.monotonic_ms()
  let mut diagnostics = 0
  let mut outbound = 0
  for tick in 1..<=3600 {
    engine.advance(1000L + tick.to_int64() * 1000L)
    while engine.poll_outbound() is Some(_) {
      outbound += 1
    }
    event_peak = event_peak.max(engine.stats().queued_events)
    while engine.poll_event() is Some(event) {
      guard event is @dnssd.Event::Diagnostic(_, _) else {
        fail("idle tick changed service content")
      }
      diagnostics += 1
    }
  }
  let idle_ms = @transport.monotonic_ms() - idle
  engine.advance(7201000L)
  let expired = engine.stats()
  guard expired.cached_records == 0 && expired.services == 0 else {
    fail("expired records retained")
  }
  engine.close()
  println(
    Json::object({
      "services": Json(size),
      "records": Json(size * 4),
      "batches": Json(batches.length()),
      "ingest_ms": Json(ingest_ms),
      "duplicate_ms": Json(repeat_ms),
      "idle_ticks": Json(3600),
      "virtual_elapsed_ms": Json(3600000),
      "idle_ms": Json(idle_ms),
      "cache_peak_records": Json(initial.cached_records),
      "event_peak": Json(event_peak),
      "query_jobs": Json(initial.query_jobs),
      "outbound_queries": Json(outbound),
      "diagnostics": Json(diagnostics),
      "dropped_events": Json(engine.dropped_events()),
      "invariants_passed": Json(true),
    }).stringify(),
  )
}
