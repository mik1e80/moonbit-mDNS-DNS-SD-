///|
test "smoke: subtype queries keep base instance identity and filter membership" {
  let records = fixture()
  let subtype = @model.DnsName::parse("_printer._sub._http._tcp.local.")
  let engine = @engine.Engine::new()
  let id = engine.browse(subtype, "wifi", 0)
  engine.advance(120)
  guard engine.poll_outbound() is Some(outbound) else {
    fail("no subtype query")
  }
  assert_true(outbound.name.same_name(subtype))
  engine.ingest_message(message(records), "wifi", 200)
  assert_true(engine.poll_event() is None)
  let membership : @wire.Record = { ..records[0], name: subtype, }
  engine.ingest_message(message([membership]), "wifi", 300)
  assert_true(engine.poll_event() is Some(@engine.Seen(_)))
  guard engine.poll_event() is Some(@engine.Resolved(snapshot)) else {
    fail("subtype did not resolve base SRV/TXT")
  }
  assert_true(snapshot.service_type.same_name(records[0].name))
  assert_true(snapshot.instance.same_name(records[1].name))
  engine.ingest_message(message([{ ..membership, ttl: 0, }]), "wifi", 400)
  engine.advance(1400)
  assert_true(engine.poll_event() is Some(@engine.Removed(_, "goodbye")))
  engine.cancel(id, 1400)
}

///|
test "smoke: base and subtype subscriptions share one lifecycle" {
  let records = fixture()
  let subtype = @model.DnsName::parse("_printer._sub._http._tcp.local.")
  let engine = @engine.Engine::new()
  let base_id = engine.browse(records[0].name, "wifi", 0)
  let _ = engine.browse(subtype, "wifi", 0)
  engine.ingest_message(message(records), "wifi", 0)
  let _ = engine.poll_event()
  let _ = engine.poll_event()
  let membership : @wire.Record = { ..records[0], name: subtype, }
  engine.ingest_message(message([membership]), "wifi", 1)
  assert_true(engine.poll_event() is None)
  assert_eq(engine.snapshots().length(), 1)
  engine.cancel(base_id, 2)
  assert_true(engine.poll_event() is None)
  assert_eq(engine.snapshots().length(), 1)
  assert_false(
    @engine.valid_service_type(
      @model.DnsName::parse("_printer._bad._http._tcp.local."),
    ),
  )
  engine.close()
}
