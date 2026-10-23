///|
fn append(out : Array[Byte], bytes : Bytes) -> Unit {
  for b in bytes {
    out.push(b)
  }
}

///|
fn put16(out : Array[Byte], n : Int32) -> Unit {
  out.push((n >> 8).to_byte())
  out.push((n & 255).to_byte())
}

///|
fn payload(record : Record) -> Bytes raise WireError {
  match (record.rr_type, record.data) {
    (1, A(bytes)) => {
      guard bytes.length() == 4 else {
        raise Malformed("invalid A known answer")
      }
      bytes
    }
    (28, Aaaa(bytes)) => {
      guard bytes.length() == 16 else {
        raise Malformed("invalid AAAA known answer")
      }
      bytes
    }
    (12, Ptr(name)) => name.to_wire()
    (16, Txt(txt)) => txt.to_wire()
    (33, Srv(priority, weight, port, target)) => {
      guard priority >= 0 &&
        priority <= 65535 &&
        weight >= 0 &&
        weight <= 65535 &&
        port >= 0 &&
        port <= 65535 else {
        raise Malformed("SRV known answer fields outside wire range")
      }
      let bytes : Array[Byte] = []
      put16(bytes, priority)
      put16(bytes, weight)
      put16(bytes, port)
      append(bytes, target.to_wire())
      Bytes::makei(bytes.length(), i => bytes[i])
    }
    _ => raise Malformed("unsupported/mismatched known answer")
  }
}

///|
/// A single bounded QM query. Oversized Known-Answer sets return an error;
/// multi-packet KA is deliberately not approximated by silent truncation.
pub fn query_with_answers(
  name : @model.DnsName,
  rr_type : Int32,
  answers : Array[Record],
) -> Bytes raise WireError {
  guard answers.length() <= 255 else {
    raise Malformed("known answer count exceeds 255")
  }
  let out = qm_query(name, rr_type).to_array()
  out[6] = (answers.length() >> 8).to_byte()
  out[7] = (answers.length() & 255).to_byte()
  for record in answers {
    guard record.rr_class == 1 &&
      record.rr_type == rr_type &&
      record.name.same_name(name) else {
      raise Malformed("known answer does not match question")
    }
    let bytes = payload(record)
    guard bytes.length() <= 65535 else {
      raise Malformed("RDATA exceeds wire length")
    }
    append(out, record.name.to_wire())
    put16(out, record.rr_type)
    put16(out, 1) // cache-flush MUST NOT appear in a query's Known Answers.
    out.push((record.ttl >> 24).to_byte())
    out.push(((record.ttl >> 16) & 255U).to_byte())
    out.push(((record.ttl >> 8) & 255U).to_byte())
    out.push((record.ttl & 255U).to_byte())
    put16(out, bytes.length())
    append(out, bytes)
    guard out.length() <= 9000 else {
      raise Malformed("single-packet known answer limit (9000 octets)")
    }
  }
  Bytes::makei(out.length(), i => out[i])
}
