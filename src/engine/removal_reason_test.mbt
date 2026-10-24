///|
test "smoke: simultaneous expirations preserve each service removal cause" {
  let records = fixture()
  let other = @model.DnsName::from_utf8_labels([
    "other", "_http", "_tcp", "local",
  ])
  let expiring : @wire.Record = { ..records[0], ttl: 2, }
  let leaving : @wire.Record = { ..records[0], data: @wire.Ptr(other), }
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message([expiring, leaving]), "wifi", 0)
  let _ = engine.poll_event()
  let _ = engine.poll_event()
  engine.ingest_message(message([{ ..leaving, ttl: 0, }]), "wifi", 1000)
  engine.advance(2000)
  match engine.poll_event() {
    Some(@engine.Removed(snapshot, "ttl_expired")) =>
      assert_true(snapshot.instance.same_name(records[1].name))
    _ => fail("first instance should expire naturally")
  }
  match engine.poll_event() {
    Some(@engine.Removed(snapshot, "goodbye")) =>
      assert_true(snapshot.instance.same_name(other))
    _ => fail("second instance should retain its goodbye cause")
  }
  assert_true(engine.poll_event() is None)
}

///|
test "smoke: unrelated expiry does not relabel an arriving service update" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message(records), "wifi", 0)
  let _ = engine.poll_event()
  let _ = engine.poll_event()
  // The same owner and RDATA on another interface must not set this event's cause.
  let other : @wire.Record = { ..records[2], ttl: 1, }
  engine.ingest_message(message([other]), "ethernet", 0)
  let txt = @model.TxtRecord::from_entries([b"demo=updated"])
  let changed : @wire.Record = { ..records[2], data: @wire.Txt(txt), }
  engine.ingest_message(message([changed]), "wifi", 1000)
  assert_true(engine.poll_event() is Some(@engine.Updated(_, "response")))
  assert_true(engine.poll_event() is None)
}

///|
test "smoke: service unavailability keeps scoped SRV removal reasons" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "wifi", 0)
  let _ = engine.browse(records[0].name, "ethernet", 0)
  engine.ingest_message(message(fixture(srv_ttl=2)), "wifi", 0)
  engine.ingest_message(message(records), "ethernet", 0)
  for _ in 0..<4 {
    let _ = engine.poll_event()
  }
  engine.ingest_message(
    message([{ ..records[1], ttl: 0, }]),
    "ethernet",
    1000,
  )
  engine.advance(2000)
  match engine.poll_event() {
    Some(@engine.Unavailable(snapshot, "ttl_expired")) =>
      assert_eq(snapshot.scope, "wifi")
    _ => fail("wifi SRV should expire naturally")
  }
  match engine.poll_event() {
    Some(@engine.Unavailable(snapshot, "goodbye")) =>
      assert_eq(snapshot.scope, "ethernet")
    _ => fail("ethernet SRV should retain its goodbye cause")
  }
  assert_true(engine.poll_event() is None)
}
