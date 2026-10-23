///|
fn a(
  last : Byte,
  ttl~ : UInt32 = 120,
  flush~ : Bool = false,
) -> @wire.Record raise {
  {
    name: @model.DnsName::from_utf8_labels(["host", "local"]),
    rr_type: 1,
    rr_class: 1,
    cache_flush: flush,
    ttl,
    data: @wire.A(Bytes::makei(4, i => if i == 3 { last } else { b'\x00' })),
    section: @wire.Answer,
  }
}

///|
fn response(
  records : Array[@wire.Record],
  flags~ : Int32 = 0x8400,
) -> @wire.Message {
  { id: 0, flags, questions: [], records, }
}

///|
test "smoke: cache ignores query known answers and isolates scopes without duplicates" {
  let cache = @cache.RecordCache::new()
  let record = a(b'\x01')
  let _ = cache.ingest("wifi", response([record], flags=0), 0)
  assert_eq(cache.len(), 0)
  let _ = cache.ingest("wifi", response([record]), 0)
  let _ = cache.ingest("wifi", response([record]), 100)
  let _ = cache.ingest("ethernet", response([record]), 100)
  assert_eq(cache.len(), 2)
  assert_eq(cache.records("wifi", record.name, 1)[0].expires_at, 120100L)
}

///|
test "smoke: goodbye grace can be rescued and has a precise removal reason" {
  let cache = @cache.RecordCache::new()
  let record = a(b'\x01')
  let _ = cache.ingest("wifi", response([record]), 0)
  let _ = cache.ingest("wifi", response([a(b'\x01', ttl=0)]), 100)
  assert_eq(cache.advance(1099).length(), 0)
  let _ = cache.ingest("wifi", response([record]), 1099)
  assert_eq(cache.advance(1100).length(), 0)
  let _ = cache.ingest("wifi", response([a(b'\x01', ttl=0)]), 2000)
  let removed = cache.advance(3000)
  assert_eq(removed.length(), 1)
  assert_eq(removed[0].reason, "goodbye")
}

///|
test "smoke: split flush burst retains recent members while old addresses expire" {
  let cache = @cache.RecordCache::new()
  let old = a(b'\x01', flush=true)
  let _ = cache.ingest("wifi", response([old]), 0)
  let _ = cache.ingest("wifi", response([a(b'\x02', flush=true)]), 2000)
  let _ = cache.ingest("wifi", response([a(b'\x03', flush=true)]), 2100)
  assert_eq(cache.len(), 3)
  let removed = cache.advance(3000)
  assert_eq(removed.length(), 1)
  assert_eq(removed[0].reason, "cache_flush")
  assert_eq(cache.records("wifi", old.name, 1).length(), 2)
}

///|
test "smoke: cache resource failure is atomic and time cannot run backwards" {
  let cache = @cache.RecordCache::new(capacity=1)
  let _ = cache.ingest("wifi", response([a(b'\x01')]), 100)
  let failed = try {
    let _ = cache.ingest("wifi", response([a(b'\x02')]), 200)
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(cache.len(), 1)
  let backward = try {
    let _ = cache.advance(99)
    false
  } catch {
    _ => true
  }
  assert_true(backward)
  let removed = cache.advance(120100)
  assert_eq(removed[0].reason, "ttl_expired")
}
