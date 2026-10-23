///|
pub impl Show for ReplayError with fn output(self, logger) {
  match self {
    InvalidCommand(detail) =>
      logger.write_string("invalid_replay_command: " + detail)
  }
}

///|
#deprecated
pub extend ReplayError with Show::{to_string, output}
