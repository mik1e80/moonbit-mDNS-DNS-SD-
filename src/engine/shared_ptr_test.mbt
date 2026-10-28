///|
test "smoke: abnormal PTR flush preserves peer services and regular PTR polling" {
  let a = capacity_fixture("_http._tcp.local.", "a", 8001)
  let b = capacity_fixture("_http._tcp.local.", "b", 8002)
  let engine = @engine.Engine::new()
  let _ = engine.browse(a[0].name, "wifi", 0)
  engine.ingest_message(message(a), "wifi", 0)
  engine.ingest_message(message(b), "wifi", 0)
  while engine.poll_event() is Some(_) {

  }
  engine.ingest_message(message([{ ..a[0], cache_flush: true, }]), "wifi", 2000)
  engine.advance(3000)
  assert_eq(engine.snapshots().length(), 2)
  assert_true(engine.snapshots().all(s => s.complete))
  assert_true(engine.poll_event() is None)
  let mut ptr_query = false
  while engine.poll_outbound() is Some(query) {
    if query.rr_type == 12 {
      ptr_query = true
    }
  }
  assert_true(ptr_query)
}
