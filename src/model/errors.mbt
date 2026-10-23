///|
pub impl Show for InputError with fn output(self, logger) {
  match self {
    InvalidInput(detail) => logger.write_string("invalid_input: " + detail)
  }
}

///|
#deprecated
pub extend InputError with Show::{to_string, output}
