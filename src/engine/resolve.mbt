///|
/// Resolve an already named instance without requiring a PTR response.
/// The timeout covers initial resolution; after success it remains subscribed
/// until cancel/close so updates keep the same event contract as browse.
pub fn Engine::resolve(
  self : Engine,
  instance : @model.DnsName,
  scope : String,
  now : Int64,
  timeout_ms~ : Int32 = 5000,
) -> Int32 raise {
  guard !self.closed else { raise Closed }
  let labels = instance.labels()
  guard labels.length() == 4 else { raise InvalidServiceType }
  let service_type = @model.DnsName::from_labels([
    labels[1],
    labels[2],
    labels[3],
  ])
  guard valid_service_type(service_type) else { raise InvalidServiceType }
  guard scope.length() > 0 && scope.length() <= 256 else {
    raise ResourceLimit("scope length outside 1..256")
  }
  guard timeout_ms > 0 && timeout_ms <= 3600000 else {
    raise ResourceLimit("resolve timeout outside 1..3600000ms")
  }
  guard self.interests.length() < 64 && self.next_id < 2147483647 else {
    raise ResourceLimit("subscription limit (64)")
  }
  let _ = self.cache.advance(now)
  self.now_ms = now
  let id = self.next_id
  self.next_id += 1
  self.interests.push({
    id,
    scope,
    service_type,
    instance: Some(instance),
    deadline: Some(now + timeout_ms.to_int64()),
  })
  self.reconcile("resolve_started")
  id
}

///|
fn Engine::expire_resolvers(self : Engine) -> Bool {
  let expired = self.interests.filter(s => {
    s.deadline is Some(time) && time <= self.now_ms
  })
  for sub in expired {
    self.emit(ResolveTimedOut(sub.id))
  }
  self.interests = self.interests.filter(s => {
    !(s.deadline is Some(time) && time <= self.now_ms)
  })
  !expired.is_empty()
}
