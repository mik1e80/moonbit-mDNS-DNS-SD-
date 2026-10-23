///|
pub suberror InputError {
  InvalidInput(String)
} derive(Debug)

///|
/// DNS labels as immutable octets. Never split an instance label on dots.
pub struct DnsName {
  priv labels : Array[Bytes]
} derive(Debug)

///|
pub fn DnsName::from_labels(labels : Array[Bytes]) -> DnsName raise InputError {
  let mut size = 1
  for label in labels {
    guard label.length() > 0 && label.length() <= 63 else {
      raise InvalidInput("DNS label must contain 1..63 octets")
    }
    size += label.length() + 1
    guard size <= 255 else {
      raise InvalidInput("DNS name exceeds 255 wire octets")
    }
  }
  { labels: labels.copy(), }
}

///|
pub fn DnsName::from_utf8_labels(
  labels : Array[String],
) -> DnsName raise InputError {
  DnsName::from_labels(labels.map(s => @utf8.encode(s)))
}

///|
pub fn DnsName::labels(self : DnsName) -> Array[Bytes] {
  self.labels.copy()
}

///|
pub fn DnsName::to_wire(self : DnsName) -> Bytes {
  let out : Array[Byte] = []
  for label in self.labels {
    out.push(label.length().to_byte())
    for b in label {
      out.push(b)
    }
  }
  out.push(0)
  Bytes::makei(out.length(), i => out[i])
}

///|
/// A collision-free wire key with ASCII case folding only.
pub fn DnsName::canonical_key(self : DnsName) -> Bytes {
  let wire = self.to_wire()
  let out = wire.to_array()
  let mut offset = 0
  for label in self.labels {
    offset += 1
    for b in label {
      let n = b.to_int()
      out[offset] = (if n >= 65 && n <= 90 { n + 32 } else { n }).to_byte()
      offset += 1
    }
  }
  Bytes::makei(out.length(), i => out[i])
}

///|
pub fn DnsName::same_name(self : DnsName, other : DnsName) -> Bool {
  self.canonical_key() == other.canonical_key()
}

///|
/// Absolute, reversible ASCII presentation. UTF-8 remains intact in labels().
pub fn DnsName::to_presentation(self : DnsName) -> String {
  let out = StringBuilder()
  for label in self.labels {
    for b in label {
      let n = b.to_int()
      if n >= 33 && n <= 126 && n != 46 && n != 92 {
        out.write_char(n.unsafe_to_char())
      } else {
        out.write_string("\\")
        out.write_char((48 + n / 100).unsafe_to_char())
        out.write_char((48 + n / 10 % 10).unsafe_to_char())
        out.write_char((48 + n % 10).unsafe_to_char())
      }
    }
    out.write_char('.')
  }
  if self.labels.is_empty() {
    "."
  } else {
    out.to_string()
  }
}
