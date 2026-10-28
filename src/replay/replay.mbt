///|
pub suberror ReplayError {
  InvalidCommand(String)
}

///|
pub struct Replay {
  engine : @engine.Engine
  priv mut now_ms : Int64
  priv seed : UInt32
  priv mut started : Bool
  priv mut configured : Bool
}

///|
pub fn Replay::new(seed~ : UInt32 = 1U) -> Replay raise {
  {
    engine: @engine.Engine::new(seed~),
    now_ms: 0,
    seed,
    started: false,
    configured: false,
  }
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
    "config" => {
      guard !self.started &&
        !self.configured &&
        at == 0L &&
        read_config_seed(object) == self.seed else {
        raise InvalidCommand(
          "config must be first, unique and match the replay seed",
        )
      }
      self.configured = true
      output.push(
        Json::object({
          "event": Json("configured"),
          "seed": Json(self.seed),
          "at_ms": Json(0),
        }),
      )
    }
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
  if kind != "config" {
    self.started = true
  }
  self.drain_events(output, at)
  while self.engine.poll_outbound() is Some(packet) {
    self.drain_events(output, at)
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
  self.drain_events(output, at)
  output
}

///|
fn Replay::drain_events(
  self : Replay,
  output : Array[Json],
  at : Int64,
) -> Unit {
  while self.engine.poll_event() is Some(event) {
    let json = event_json(event)
    if json is Json::Object(fields) {
      fields["at_ms"] = Json(at.to_double())
    }
    output.push(json)
  }
}

///|
fn read_config_seed(object : Map[String, Json]) -> UInt32 raise {
  let kind = text(object, "kind")
  let format : Int32 = @json.from_json(field(object, "format"))
  guard kind == "config" && format == 1 else {
    raise InvalidCommand("unsupported trace configuration/format")
  }
  let value : Double = @json.from_json(field(object, "seed"))
  guard value >= 0.0 && value <= 4294967295.0 else {
    raise InvalidCommand("seed outside UInt32 range")
  }
  let n = value.to_int64()
  guard n.to_double() == value else {
    raise InvalidCommand("fractional replay seed")
  }
  n.to_int().reinterpret_as_uint()
}

///|
pub fn Replay::from_config(line : String) -> Replay raise {
  guard line.length() <= 32768 else {
    raise InvalidCommand("config line too long")
  }
  let object : Map[String, Json] = @json.from_json(
    @json.parse(line, max_nesting_depth=16, reject_duplicate_keys=true),
  )
  Replay::new(seed=read_config_seed(object))
}
