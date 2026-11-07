///|
/// Structured error emitted after a provider stream has started.
///
/// `message` is always suitable for display. `data` retains the provider or
/// parser payload when one is available, matching AI SDK's non-string V4
/// stream error value without relying on a dynamically typed `unknown`.
#derive(Debug, Eq)
pub(all) struct StreamErrorInfo {
  message : String
  data : Json?
}

///|
/// Construct a stream error with optional structured data.
pub fn StreamErrorInfo::new(message : String, data? : Json) -> StreamErrorInfo {
  { message, data, }
}

///|
#deprecated
pub extend StreamErrorInfo with Debug::{to_repr}

///|
#deprecated
pub extend StreamErrorInfo with Eq::{not_equal, equal}
