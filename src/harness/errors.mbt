///|
/// Base error for failures originating in a harness adapter.
pub(all) suberror HarnessError {
  HarnessError(message~ : String, cause~ : String?)
} derive(Debug, Eq)

///|
/// Raised when a harness or sandbox cannot provide a requested capability.
pub(all) suberror HarnessCapabilityUnsupportedError {
  HarnessCapabilityUnsupportedError(
    message~ : String,
    harness_id~ : String?,
    cause~ : String?
  )
} derive(Debug, Eq)

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
