///|
pub impl Show for TransportError with fn output(self, logger) {
  match self {
    SocketError(context, code) =>
      logger.write_string("transport_error: \{context} (OS/code \{code})")
  }
}

///|
#deprecated
pub extend TransportError with Show::{to_string, output}
