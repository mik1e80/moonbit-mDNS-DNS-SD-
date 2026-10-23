///|
pub suberror EngineError {
  Closed
  InvalidServiceType
  ResourceLimit(String)
  UnknownSubscription
}

///|
pub struct ServiceSnapshot {
  scope : String
  service_type : @model.DnsName
  instance : @model.DnsName
  target : @model.DnsName?
  port : Int32?
  txt : @model.TxtRecord?
  addresses : Array[Bytes]
  missing : Array[String]
  complete : Bool
  remaining_ttl_ms : Int64
}

///|
pub(all) enum Event {
  Seen(ServiceSnapshot)
  Resolved(ServiceSnapshot)
  Updated(ServiceSnapshot, String)
  Unavailable(ServiceSnapshot, String)
  Removed(ServiceSnapshot, String)
  Diagnostic(String, String)
  ResolveTimedOut(Int32)
}

///|
struct Subscription {
  id : Int32
  scope : String
  service_type : @model.DnsName
  instance : @model.DnsName?
  deadline : Int64?
}

///|
pub struct Engine {
  priv cache : @cache.RecordCache
  priv mut interests : Array[Subscription]
  priv mut services : Array[ServiceSnapshot]
  priv events : Array[Event]
  priv event_capacity : Int32
  priv service_capacity : Int32
  priv mut next_id : Int32
  priv mut now_ms : Int64
  priv mut closed : Bool
  priv mut lost : Int64
  priv mut jobs : Array[QueryJob]
  priv mut pending : Array[QuestionSpec]
  priv query_capacity : Int32
  priv mut rng : UInt32
}

///|
pub fn Engine::new(
  cache_capacity~ : Int32 = 2048,
  service_capacity~ : Int32 = 512,
  event_capacity~ : Int32 = 256,
  query_capacity~ : Int32 = 256,
  seed~ : UInt32 = 1U,
) -> Engine raise {
  guard service_capacity > 0 &&
    service_capacity <= 4096 &&
    event_capacity >= 2 &&
    event_capacity <= 16384 else {
    raise ResourceLimit("invalid service/event capacity")
  }
  guard query_capacity > 0 && query_capacity <= 8192 else {
    raise ResourceLimit("invalid query capacity")
  }
  {
    cache: @cache.RecordCache::new(capacity=cache_capacity),
    interests: [],
    services: [],
    events: [],
    event_capacity,
    service_capacity,
    next_id: 1,
    now_ms: 0,
    closed: false,
    lost: 0,
    jobs: [],
    pending: [],
    query_capacity,
    rng: seed,
  }
}

///|
fn clone_snapshot(s : ServiceSnapshot) -> ServiceSnapshot {
  { ..s, addresses: s.addresses.copy(), missing: s.missing.copy(), }
}

///|
fn Engine::emit(self : Engine, event : Event) -> Unit {
  if self.events.length() >= self.event_capacity {
    self.lost += self.events.length().to_int64()
    self.events.clear()
    self.events.push(
      Diagnostic(
        "event_overflow", "queued events discarded; resync from snapshots()",
      ),
    )
  }
  self.events.push(event)
}

///|
pub fn valid_service_type(name : @model.DnsName) -> Bool {
  let labels = name.labels()
  if labels.length() != 3 {
    return false
  }
  let suffix = labels
  // Compare via DNS names so only ASCII case is folded.
  let transport = @model.DnsName::from_labels([suffix[1], suffix[2]]) catch {
    _ => return false
  }
  let tcp = @model.DnsName::from_labels([b"_tcp", b"local"]) catch {
    _ => return false
  }
  let udp = @model.DnsName::from_labels([b"_udp", b"local"]) catch {
    _ => return false
  }
  if !transport.same_name(tcp) && !transport.same_name(udp) {
    return false
  }
  let first = labels[0]
  if first.length() < 2 || first.length() > 16 || first[0] != b'_' {
    return false
  }
  let mut letter = false
  for i in 1..<first.length() {
    let n = first[i].to_int()
    if (n >= 65 && n <= 90) || (n >= 97 && n <= 122) {
      letter = true
    } else if n >= 48 && n <= 57 {
      ()
    } else if n == 45 && i > 1 && i < first.length() - 1 && first[i - 1] != b'-' {
      ()
    } else {
      return false
    }
  }
  letter
}

///|
fn is_instance(
  instance : @model.DnsName,
  service_type : @model.DnsName,
) -> Bool {
  let labels = instance.labels()
  if labels.length() != 4 {
    return false
  }
  let suffix = @model.DnsName::from_labels([labels[1], labels[2], labels[3]]) catch {
    _ => return false
  }
  suffix.same_name(service_type)
}

///|
pub fn Engine::browse(
  self : Engine,
  service_type : @model.DnsName,
  scope : String,
  now : Int64,
) -> Int32 raise {
  guard !self.closed else { raise Closed }
  guard valid_service_type(service_type) else { raise InvalidServiceType }
  guard scope.length() > 0 && scope.length() <= 256 else {
    raise ResourceLimit("scope length outside 1..256")
  }
  guard self.interests.length() < 64 && self.next_id < 2147483647 else {
    raise ResourceLimit("subscription limit (64)")
  }
  let removed = self.cache.advance(now)
  self.now_ms = now
  let id = self.next_id
  self.next_id += 1
  self.interests.push({
    id,
    scope,
    service_type,
    instance: None,
    deadline: None,
  })
  self.reconcile(
    if removed.is_empty() {
      "subscribed"
    } else {
      removed[0].reason
    },
  )
  id
}

///|
fn newest(records : Array[@cache.CachedRecord]) -> Array[@cache.CachedRecord] {
  let mut time : Int64 = -1
  for entry in records {
    if entry.received_at > time {
      time = entry.received_at
    }
  }
  records.filter(e => e.received_at == time)
}

///|
fn Engine::build_snapshot(
  self : Engine,
  sub : Subscription,
  ptr_expiry : Int64,
  instance : @model.DnsName,
) -> ServiceSnapshot {
  let missing : Array[String] = []
  let mut target : @model.DnsName? = None
  let mut port : Int32? = None
  let mut txt : @model.TxtRecord? = None
  let mut expiry = ptr_expiry
  let srv_records = newest(self.cache.records(sub.scope, instance, 33))
  if srv_records.length() != 1 {
    missing.push(if srv_records.is_empty() { "srv" } else { "ambiguous_srv" })
  } else if srv_records[0].record.data is @wire.Srv(_, _, p, host) {
    if host.labels().is_empty() || p == 0 {
      missing.push("unavailable_srv")
    } else {
      target = Some(host)
      port = Some(p)
    }
    expiry = expiry.min(srv_records[0].expires_at)
  }
  let txt_records = newest(self.cache.records(sub.scope, instance, 16))
  if txt_records.length() != 1 {
    missing.push(if txt_records.is_empty() { "txt" } else { "ambiguous_txt" })
  } else if txt_records[0].record.data is @wire.Txt(value) {
    txt = Some(value)
    expiry = expiry.min(txt_records[0].expires_at)
  }
  let addresses : Array[Bytes] = []
  if target is Some(host) {
    let all = self.cache.records(sub.scope, host, 1)
    for record in self.cache.records(sub.scope, host, 28) {
      all.push(record)
    }
    for record in all {
      match record.record.data {
        @wire.A(bytes) | @wire.Aaaa(bytes) => {
          addresses.push(bytes)
          expiry = expiry.min(record.expires_at)
        }
        _ => ()
      }
    }
  }
  addresses.sort()
  if addresses.is_empty() {
    missing.push("addresses")
  }
  {
    scope: sub.scope,
    service_type: sub.service_type,
    instance,
    target,
    port,
    txt,
    addresses,
    missing,
    complete: missing.is_empty(),
    remaining_ttl_ms: (expiry - self.now_ms).max(0L),
  }
}

///|
fn same_identity(a : ServiceSnapshot, b : ServiceSnapshot) -> Bool {
  a.scope == b.scope &&
  a.instance.same_name(b.instance) &&
  a.service_type.same_name(b.service_type)
}

///|
fn same_content(a : ServiceSnapshot, b : ServiceSnapshot) -> Bool {
  a.target.map(t => t.canonical_key()) == b.target.map(t => t.canonical_key()) &&
  a.port == b.port &&
  a.txt.map(t => t.to_wire()) == b.txt.map(t => t.to_wire()) &&
  a.addresses == b.addresses &&
  a.missing == b.missing
}

///|
fn Engine::reconcile(self : Engine, reason : String) -> Unit {
  let current : Array[ServiceSnapshot] = []
  let mut limited = false
  for sub in self.interests {
    if sub.instance is Some(instance) {
      if !self.cache.records(sub.scope, instance, 33).is_empty() ||
        !self.cache.records(sub.scope, instance, 16).is_empty() {
        let snapshot = self.build_snapshot(sub, 9223372036854775807L, instance)
        if !current.any(s => same_identity(s, snapshot)) {
          if current.length() < self.service_capacity {
            current.push(snapshot)
          } else {
            limited = true
          }
        }
      }
      continue
    }
    for ptr in self.cache.records(sub.scope, sub.service_type, 12) {
      if ptr.record.data is @wire.Ptr(instance) {
        if !is_instance(instance, sub.service_type) {
          self.emit(
            Diagnostic(
              "unsupported_instance_domain", "PTR target outside the subscribed local service type",
            ),
          )
          continue
        }
        let snapshot = self.build_snapshot(sub, ptr.expires_at, instance)
        if current.any(s => same_identity(s, snapshot)) {
          continue
        }
        if current.length() >= self.service_capacity {
          limited = true
          continue
        }
        current.push(snapshot)
      }
    }
  }
  if limited {
    self.emit(Diagnostic("service_limit", "additional instances omitted"))
  }
  for old in self.services {
    if !current.any(s => same_identity(s, old)) {
      self.emit(
        Removed(
          { ..clone_snapshot(old), complete: false, remaining_ttl_ms: 0, },
          reason,
        ),
      )
    }
  }
  for snapshot in current {
    let mut previous : ServiceSnapshot? = None
    for old in self.services {
      if same_identity(old, snapshot) {
        previous = Some(old)
        break
      }
    }
    match previous {
      None => {
        self.emit(Seen(clone_snapshot(snapshot)))
        if snapshot.complete {
          self.emit(Resolved(clone_snapshot(snapshot)))
        }
      }
      Some(old) =>
        if old.complete && !snapshot.complete {
          self.emit(Unavailable(clone_snapshot(snapshot), reason))
        } else if !old.complete && snapshot.complete {
          self.emit(Resolved(clone_snapshot(snapshot)))
        } else if !same_content(old, snapshot) {
          self.emit(Updated(clone_snapshot(snapshot), reason))
        }
    }
  }
  self.services = current
  self.interests = self.interests.map(sub => {
    if sub.instance is Some(instance) &&
      current.any(s => {
        s.scope == sub.scope && s.instance.same_name(instance) && s.complete
      }) {
      { ..sub, deadline: None, }
    } else {
      sub
    }
  })
  self.sync_queries()
  self.schedule_queries()
}

///|
pub fn Engine::ingest(
  self : Engine,
  packet : Bytes,
  scope : String,
  now : Int64,
) -> Unit raise {
  guard !self.closed else { raise Closed }
  let message = @wire.decode(packet)
  self.ingest_message(message, scope, now)
}

///|
pub fn Engine::ingest_message(
  self : Engine,
  message : @wire.Message,
  scope : String,
  now : Int64,
) -> Unit raise {
  guard !self.closed else { raise Closed }
  let removed = self.cache.ingest(scope, message, now)
  self.now_ms = now
  if self.expire_resolvers() {
    self.reconcile("resolve_timeout")
    return
  }
  self.reconcile(
    if removed.is_empty() {
      "response"
    } else {
      removed[0].reason
    },
  )
}

///|
pub fn Engine::advance(self : Engine, now : Int64) -> Unit raise {
  guard !self.closed else { raise Closed }
  let removed = self.cache.advance(now)
  self.now_ms = now
  if self.expire_resolvers() {
    self.reconcile("resolve_timeout")
    return
  }
  self.reconcile(if removed.is_empty() { "time" } else { removed[0].reason })
}

///|
pub fn Engine::cancel(self : Engine, id : Int32, now : Int64) -> Unit raise {
  guard !self.closed else { raise Closed }
  guard self.interests.any(s => s.id == id) else { raise UnknownSubscription }
  let _ = self.cache.advance(now)
  self.now_ms = now
  self.interests = self.interests.filter(s => s.id != id)
  self.reconcile("cancelled")
}

///|
pub fn Engine::close(self : Engine) -> Unit {
  if self.closed {
    return
  }
  self.interests = []
  self.reconcile("closed")
  self.cache.clear()
  self.closed = true
}

///|
pub fn Engine::snapshots(self : Engine) -> Array[ServiceSnapshot] {
  self.services.map(clone_snapshot)
}

///|
pub fn Engine::poll_event(self : Engine) -> Event? {
  if self.events.is_empty() {
    None
  } else {
    Some(self.events.remove(0))
  }
}

///|
pub fn Engine::dropped_events(self : Engine) -> Int64 {
  self.lost
}

///|
pub fn Engine::next_deadline(self : Engine) -> Int64? {
  if self.closed {
    return None
  }
  let mut result = self.cache.next_deadline()
  if !self.pending.is_empty() {
    result = Some(self.now_ms)
  }
  for job in self.jobs {
    for deadline in [job.regular_at, job.refresh_at] {
      if deadline is Some(time) {
        if result is None || (result is Some(old) && time < old) {
          result = Some(time)
        }
      }
    }
  }
  for sub in self.interests {
    if sub.deadline is Some(time) {
      if result is None || (result is Some(old) && time < old) {
        result = Some(time)
      }
    }
  }
  result
}
