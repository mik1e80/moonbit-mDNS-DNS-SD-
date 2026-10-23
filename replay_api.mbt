///|
pub using @replay {type Replay, type ReplayError}

///|
pub fn event_json(event : Event) -> Json {
  @replay.event_json(event)
}

///|
pub fn snapshot_json(snapshot : ServiceSnapshot) -> Json {
  @replay.snapshot_json(snapshot)
}
