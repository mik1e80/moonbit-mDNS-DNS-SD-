///|
pub fn bytes_hex(data : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for b in data {
    out.write_char(digits[b.to_int() >> 4].unsafe_to_char())
    out.write_char(digits[b.to_int() & 15].unsafe_to_char())
  }
  out.to_string()
}

///|
fn hex_digit(n : Int32) -> Int32 raise InputError {
  if n >= 48 && n <= 57 {
    n - 48
  } else if n >= 65 && n <= 70 {
    n - 55
  } else if n >= 97 && n <= 102 {
    n - 87
  } else {
    raise InvalidInput("invalid hexadecimal digit")
  }
}

///|
pub fn bytes_from_hex(text : String) -> Bytes raise InputError {
  guard text.length() % 2 == 0 && text.length() <= 131070 else {
    raise InvalidInput(
      "hex input must have even length and decode to at most 65535 bytes",
    )
  }
  Bytes::makei(text.length() / 2, i => {
    ((hex_digit(text[2 * i].to_int()) << 4) |
    hex_digit(text[2 * i + 1].to_int())).to_byte()
  })
}

///|
pub fn address_text(bytes : Bytes) -> String raise InputError {
  if bytes.length() == 4 {
    "\{bytes[0].to_int()}.\{bytes[1].to_int()}.\{bytes[2].to_int()}.\{bytes[3].to_int()}"
  } else if bytes.length() == 16 {
    let groups : Array[String] = []
    for i in 0..<8 {
      groups.push(
        ((bytes[2 * i].to_int() << 8) | bytes[2 * i + 1].to_int()).to_string(
          radix=16,
        ),
      )
    }
    groups.join(":")
  } else {
    raise InvalidInput("address must contain 4 or 16 octets")
  }
}

///|
/// Parse reversible DNS presentation, including escaped octets and UTF-8.
/// Use from_utf8_labels when an instance label already has known boundaries.
pub fn DnsName::parse(text : String) -> DnsName raise InputError {
  if text == "." {
    return DnsName::from_labels([])
  }
  let data = @utf8.encode(text)
  guard data.length() > 0 && data.length() <= 1024 else {
    raise InvalidInput("name presentation length outside 1..1024")
  }
  let labels : Array[Bytes] = []
  let label : Array[Byte] = []
  let mut at = 0
  while at < data.length() {
    let b = data[at]
    if b == b'.' {
      guard !label.is_empty() else { raise InvalidInput("empty DNS label") }
      labels.push(Bytes::makei(label.length(), i => label[i]))
      label.clear()
      at += 1
    } else if b == b'\\' {
      guard at + 1 < data.length() else {
        raise InvalidInput("incomplete name escape")
      }
      let n = data[at + 1].to_int()
      if n >= 48 && n <= 57 {
        guard at + 3 < data.length() else {
          raise InvalidInput("decimal name escape requires three digits")
        }
        let a = data[at + 2].to_int() - 48
        let c = data[at + 3].to_int() - 48
        guard a >= 0 && a <= 9 && c >= 0 && c <= 9 else {
          raise InvalidInput("invalid decimal name escape")
        }
        let value = (n - 48) * 100 + a * 10 + c
        guard value <= 255 else {
          raise InvalidInput("name escape exceeds one octet")
        }
        label.push(value.to_byte())
        at += 4
      } else {
        label.push(data[at + 1])
        at += 2
      }
    } else {
      label.push(b)
      at += 1
    }
  }
  if !label.is_empty() {
    labels.push(Bytes::makei(label.length(), i => label[i]))
  }
  DnsName::from_labels(labels)
}
