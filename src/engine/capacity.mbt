///|
/// Rebuild an announced instance only from a still-active subscription and live
/// membership/evidence. Capacity alone never turns it into a removed service.
fn Engine::retained_snapshot(
  self : Engine,
  old : ServiceSnapshot,
) -> ServiceSnapshot? {
  for sub in self.interests {
    if sub.scope != old.scope || !sub.service_type.same_name(old.service_type) {
      continue
    }
    if sub.instance is Some(instance) {
      if instance.same_name(old.instance) &&
        (
          !self.cache.records(sub.scope, instance, 33).is_empty() ||
          !self.cache.records(sub.scope, instance, 16).is_empty()
        ) {
        return Some(self.build_snapshot(sub, 9223372036854775807L, instance))
      }
    } else {
      for ptr in self.cache.records(sub.scope, sub.browse_name, 12) {
        if ptr.record.data is @wire.Ptr(instance) &&
          instance.same_name(old.instance) {
          return Some(self.build_snapshot(sub, ptr.expires_at, instance))
        }
      }
    }
  }
  None
}
