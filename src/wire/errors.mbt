///|
pub impl Show for WireError with fn output(self, logger) {
  match self {
    Malformed(detail) => logger.write_string("malformed_packet: " + detail)
  }
}

///|
#deprecated
pub extend WireError with Show::{to_string, output}
