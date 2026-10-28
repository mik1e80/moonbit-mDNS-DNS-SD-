///|
fn capacity_fixture(
  service : String,
  label : String,
  port : Int32,
) -> Array[@wire.Record] raise {
  let original = fixture()
  let kind = @model.DnsName::parse(service)
  let labels = kind.labels()
  let instance = @model.DnsName::from_labels([
    @model.DnsName::from_utf8_labels([label]).labels()[0],
    labels[0],
    labels[1],
    labels[2],
  ])
  let host = original[3].name
  [
    { ..original[0], name: kind, data: @wire.Ptr(instance), },
    { ..original[1], name: instance, data: @wire.Srv(0, 0, port, host), },
    { ..original[2], name: instance, },
    original[3],
  ]
}

///|
test "smoke: capacity retains announced services until real removal frees a slot" {
  let a = capacity_fixture("_http._tcp.local.", "a", 8001)
  let b = capacity_fixture("_ssh._tcp.local.", "b", 22)
  let c = capacity_fixture("_http._tcp.local.", "c", 8003)
  let engine = @engine.Engine::new(service_capacity=2)
  let _ = engine.browse(a[0].name, "wifi", 0)
  let _ = engine.browse(b[0].name, "wifi", 0)
  engine.ingest_message(message(a), "wifi", 0)
  engine.ingest_message(message(b), "wifi", 1)
  while engine.poll_event() is Some(_) {

  }
  engine.ingest_message(message(c), "wifi", 2)
  let snapshots = engine.snapshots()
  assert_eq(snapshots.length(), 2)
  assert_true(snapshots.any(s => s.instance.same_name(a[1].name)))
  assert_true(snapshots.any(s => s.instance.same_name(b[1].name)))
  assert_false(snapshots.any(s => s.instance.same_name(c[1].name)))
  assert_true(
    engine.poll_event() is Some(@engine.Diagnostic("service_limit", _)),
  )
  assert_true(engine.poll_event() is None)
  engine.ingest_message(message([{ ..b[0], ttl: 0, }]), "wifi", 100)
  while engine.poll_event() is Some(event) {
    assert_true(event is @engine.Diagnostic("service_limit", _))
  }
  engine.advance(1100)
  guard engine.poll_event() is Some(@engine.Removed(snapshot, "goodbye")) else {
    fail("confirmed goodbye should remove the old instance")
  }
  assert_true(snapshot.instance.same_name(b[1].name))
  assert_true(engine.poll_event() is Some(@engine.Seen(_)))
  assert_true(engine.poll_event() is Some(@engine.Resolved(_)))
  assert_true(engine.poll_event() is None)
  assert_true(engine.snapshots().any(s => s.instance.same_name(c[1].name)))
}

///|
test "smoke: a browse newcomer cannot evict an established explicit resolve" {
  let a = capacity_fixture("_http._tcp.local.", "new", 8001)
  let b = capacity_fixture("_ssh._tcp.local.", "resolved", 22)
  let engine = @engine.Engine::new(service_capacity=1)
  let _ = engine.browse(a[0].name, "wifi", 0)
  let _ = engine.resolve(b[1].name, "wifi", 0)
  engine.ingest_message(message([b[1], b[2], b[3]]), "wifi", 1)
  while engine.poll_event() is Some(_) {

  }
  engine.ingest_message(message(a), "wifi", 2)
  assert_eq(engine.snapshots().length(), 1)
  assert_true(engine.snapshots()[0].instance.same_name(b[1].name))
  assert_true(
    engine.poll_event() is Some(@engine.Diagnostic("service_limit", _)),
  )
  assert_true(engine.poll_event() is None)
}
