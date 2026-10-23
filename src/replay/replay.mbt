///|
pub suberror ReplayError {
  InvalidCommand(String)
}

///|
pub struct Replay {
  engine : @engine.Engine
  priv mut now_ms : Int64
}

///|
pub fn Replay::new(seed~ : UInt32 = 1U) -> Replay raise {
  { engine: @engine.Engine::new(seed~), now_ms: 0, }
}

///|
fn field(object : Map[String, Json], key : String) -> Json raise ReplayError {
  match object.get(key) {
    Some(value) => value
    None => raise InvalidCommand("missing field: " + key)
  }
}

///|
fn text(object : Map[String, Json], key : String) -> String raise {
  @json.from_json(field(object, key))
}

///|
pub fn Replay::step_line(self : Replay, line : String) -> Array[Json] raise {
  guard line.length() <= 32768 else {
    raise InvalidCommand("line exceeds 32768 characters")
  }
  let object : Map[String, Json] = @json.from_json(
    @json.parse(line, max_nesting_depth=16, reject_duplicate_keys=true),
  )
  let kind = text(object, "kind")
  let numeric_time : Double = @json.from_json(field(object, "at_ms"))
  guard numeric_time >= 0.0 && numeric_time <= 9007199254740991.0 else {
    raise InvalidCommand("time outside exact JSON integer range")
  }
  let at = numeric_time.to_int64()
  guard at.to_double() == numeric_time else {
    raise InvalidCommand("fractional replay time")
  }
  guard at >= self.now_ms && at <= 9223367741887480807L else {
    raise InvalidCommand("non-monotonic or overflowing time")
  }
  let output : Array[Json] = []
  match kind {
    "browse" => {
      let id = self.engine.browse(
        @model.DnsName::parse(text(object, "name")),
        text(object, "scope"),
        at,
      )
      output.push(
        Json::object({
          "event": Json("subscribed"),
          "id": Json(id),
          "at_ms": Json(at.to_double()),
        }),
      )
    }
    "resolve" => {
      let timeout : Int32 = match object.get("timeout_ms") {
        Some(value) => @json.from_json(value)
        None => 5000
      }
      let id = self.engine.resolve(
        @model.DnsName::parse(text(object, "name")),
        text(object, "scope"),
        at,
        timeout_ms=timeout,
      )
      output.push(
        Json::object({
          "event": Json("resolving"),
          "id": Json(id),
          "at_ms": Json(at.to_double()),
        }),
      )
    }
    "packet" => {
      let scope = text(object, "scope")
      let packet = @model.bytes_from_hex(text(object, "packet_hex"))
      self.engine.ingest(packet, scope, at) catch {
        error => {
          self.engine.advance(at)
          output.push(
            Json::object({
              "event": Json("diagnostic"),
              "code": Json("packet_rejected"),
              "detail": Json("\{error}"),
              "at_ms": Json(at.to_double()),
            }),
          )
        }
      }
    }
    "advance" => self.engine.advance(at)
    "cancel" => {
      let id : Int32 = @json.from_json(field(object, "id"))
      self.engine.cancel(id, at)
    }
    "close" => {
      self.engine.advance(at)
      self.engine.close()
    }
    _ => raise InvalidCommand("unknown kind: " + kind)
  }
  self.now_ms = at
  while self.engine.poll_event() is Some(event) {
    let json = event_json(event)
    if json is Json::Object(fields) {
      fields["at_ms"] = Json(at.to_double())
    }
    output.push(json)
  }
  while self.engine.poll_outbound() is Some(packet) {
    output.push(
      Json::object({
        "event": Json("outbound"),
        "at_ms": Json(at.to_double()),
        "scope": Json(packet.scope),
        "rr_type": Json(packet.rr_type),
        "packet_hex": Json(@model.bytes_hex(packet.bytes)),
      }),
    )
  }
  output
}
