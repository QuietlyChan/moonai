///|
fn anthropic_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}
