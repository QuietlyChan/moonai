///|
/// An argument passed to an `ai` utility or operation is invalid.
///
/// Mirrors upstream's ai-layer `AI_InvalidArgumentError`, which carries the
/// offending `parameter` and `value` next to the message. Kept separate from
/// the provider-level `@provider.InvalidArgumentError`, whose field is
/// `argument` and which stays reserved for provider-side diagnostics.
pub(all) suberror InvalidArgumentError {
  InvalidArgumentError(parameter~ : String, value~ : Json, message~ : String)
} derive(Debug, Eq)

///|
/// Build an `InvalidArgumentError` with the upstream message shape
/// ("Invalid argument for parameter X: …").
pub fn invalid_argument(
  parameter~ : String,
  value~ : Json,
  message~ : String,
) -> InvalidArgumentError {
  let rendered = "Invalid argument for parameter \{parameter}: \{message}"
  InvalidArgumentError(parameter~, value~, message=rendered)
}
