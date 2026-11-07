///|
/// Base error for failures originating in a harness adapter.
#derive(Debug, Eq)
pub(all) suberror HarnessError {
  HarnessError(message~ : String, cause~ : String?)
}

///|
/// Raised when a harness or sandbox cannot provide a requested capability.
#derive(Debug, Eq)
pub(all) suberror HarnessCapabilityUnsupportedError {
  HarnessCapabilityUnsupportedError(
    message~ : String,
    harness_id~ : String?,
    cause~ : String?
  )
}

///|
/// Construct an unsupported-capability error.
pub fn HarnessCapabilityUnsupportedError::new(
  message~ : String,
  harness_id? : String,
  cause? : String,
) -> HarnessCapabilityUnsupportedError {
  HarnessCapabilityUnsupportedError(message~, harness_id~, cause~)
}

///|
fn harness_error(message : String) -> HarnessError {
  HarnessError(message~, cause=None)
}

///|
#deprecated
pub extend HarnessError with Debug::{to_repr}

///|
#deprecated
pub extend HarnessError with Eq::{not_equal, equal}

///|
#deprecated
pub extend HarnessCapabilityUnsupportedError with Debug::{to_repr}

///|
#deprecated
pub extend HarnessCapabilityUnsupportedError with Eq::{not_equal, equal}
