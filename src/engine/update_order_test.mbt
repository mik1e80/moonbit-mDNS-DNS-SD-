///|
test "smoke: same-millisecond TXT packets use arrival order without false unavailability" {
  let records = fixture()
  let engine = @engine.Engine::new()
  let _ = engine.browse(records[0].name, "wifi", 0)
  engine.ingest_message(message(records), "wifi", 0)
  let _ = engine.poll_event()
  let _ = engine.poll_event()
  let txt = @model.TxtRecord::from_entries([b"demo=second"])
  let changed : @wire.Record = { ..records[2], data: @wire.Txt(txt), }
  engine.ingest_message(message([changed]), "wifi", 0)
  match engine.poll_event() {
    Some(@engine.Updated(snapshot, "response")) => {
      assert_true(snapshot.complete)
      assert_eq(snapshot.txt.unwrap().lookup("demo"), @model.Value(b"second"))
    }
    _ => fail("expected stable content update, not ambiguous/unavailable")
  }
  assert_true(engine.poll_event() is None)
}
