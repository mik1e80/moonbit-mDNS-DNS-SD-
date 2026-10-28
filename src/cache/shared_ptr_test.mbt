///|
test "smoke: abnormal PTR flush cannot evict peer instances or change goodbye grace" {
  let owner = @model.DnsName::parse("_http._tcp.local.")
  let first : @wire.Record = {
    name: owner,
    rr_type: 12,
    rr_class: 1,
    cache_flush: false,
    ttl: 120U,
    data: @wire.Ptr(@model.DnsName::parse("a._http._tcp.local.")),
    section: @wire.Answer,
  }
  let second : @wire.Record = {
    ..first,
    data: @wire.Ptr(@model.DnsName::parse("b._http._tcp.local.")),
  }
  let cache = @cache.RecordCache::new()
  let _ = cache.ingest("wifi", response([first, second]), 0)
  let _ = cache.ingest(
    "wifi",
    response([{ ..first, cache_flush: true, }]),
    2000,
  )
  assert_true(cache.advance(3000).is_empty())
  let retained = cache.records("wifi", owner, 12)
  assert_eq(retained.length(), 2)
  assert_true(retained.all(r => !r.record.cache_flush))
  let _ = cache.ingest(
    "wifi",
    response([{ ..first, cache_flush: true, ttl: 0, }]),
    4000,
  )
  let removed = cache.advance(5000)
  assert_eq(removed.length(), 1)
  assert_eq(removed[0].reason, "goodbye")
  assert_true(@cache.same_data(removed[0].record.data, first.data))
  assert_eq(cache.records("wifi", owner, 12).length(), 1)
}
